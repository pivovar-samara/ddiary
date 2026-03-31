import Foundation
import AuthenticationServices
import CryptoKit
import UIKit
import Security

// MARK: - Configuration

/// Configure these values for your Google OAuth client.
/// - Note: You must register your bundle's redirect URI scheme in your Info.plist (URL Types).
public enum GoogleOAuthConfig {
    private static var redirectURIOverride: String?

    /// Your OAuth 2.0 Client ID from Google Cloud Console (iOS type or Web type depending on flow).
    public static var clientID: String {
        sanitizedInfoValue(forKey: "GOOGLE_OAUTH_KEY") ?? ""
    }

    /// The full redirect URI registered with Google, e.g., "ddiary:/goauth".
    public static var redirectURI: String {
        get {
            if let override = redirectURIOverride?.trimmingCharacters(in: .whitespacesAndNewlines),
               !override.isEmpty {
                return override
            }
            if let configured = sanitizedInfoValue(forKey: "GOOGLE_OAUTH_REDIRECT_URI") {
                return configured
            }
            if let derived = derivedRedirectURI(fromClientID: clientID) {
                return derived
            }
            return "ddiary:/oauthredirect"
        }
        set {
            redirectURIOverride = newValue
        }
    }

    /// Optional override for callback scheme in ASWebAuthenticationSession.
    public static var callbackSchemeOverride: String?
    /// Callback scheme used by ASWebAuthenticationSession.
    /// By default this is derived from `redirectURI` to keep the flow consistent.
    public static var redirectScheme: String {
        if let override = callbackSchemeOverride?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return override
        }
        if let scheme = URL(string: redirectURI)?.scheme,
           !scheme.isEmpty {
            return scheme
        }
        return "ddiary"
    }
    public static let driveFileScope = "https://www.googleapis.com/auth/drive.file"

    /// Space-separated scopes requested in a single consent screen.
    /// Installed-app OAuth does not support incremental authorization.
    ///
    /// `drive.file` grants full Sheets API access to app-created files,
    /// so the broader `spreadsheets` scope is not needed.
    public static var scope: String = driveFileScope

    /// Scopes that must be granted for sync to function.
    /// Optional identity scopes (openid/email/profile) must not block connection.
    public static var requiredScopes: Set<String> { [driveFileScope] }

    private static func sanitizedInfoValue(forKey key: String) -> String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$(") else { return nil }
        return trimmed
    }

    private static func derivedRedirectURI(fromClientID clientID: String) -> String? {
        let suffix = ".apps.googleusercontent.com"
        guard clientID.hasSuffix(suffix), clientID.count > suffix.count else {
            return nil
        }
        let rawID = String(clientID.dropLast(suffix.count))
        guard !rawID.isEmpty else { return nil }
        return "com.googleusercontent.apps.\(rawID):/oauthredirect"
    }
}

// MARK: - Tokens

public struct GoogleOAuthTokens: Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let idToken: String?
    public let expiresIn: Int?

    public init(accessToken: String, refreshToken: String, idToken: String?, expiresIn: Int?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.idToken = idToken
        self.expiresIn = expiresIn
    }
}

// MARK: - ID Token parsing (best-effort, unsigned)

public enum GoogleIDToken: Sendable {
    /// Extracts a user identifier (email preferred, otherwise sub) from an ID token if present.
    public static func userIdentifier(from idToken: String?) -> String? {
        guard let idToken, let payload = decodeJWTPayload(idToken),
              let dict = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else { return nil }
        if let email = dict["email"] as? String { return email }
        if let sub = dict["sub"] as? String { return sub }
        return nil
    }

    private static func decodeJWTPayload(_ jwt: String) -> Data? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var base64 = String(parts[1])
        // Base64url -> Base64
        base64 = base64.replacingOccurrences(of: "-", with: "+")
        base64 = base64.replacingOccurrences(of: "_", with: "/")
        let padding = 4 - (base64.count % 4)
        if padding < 4 { base64 += String(repeating: "=", count: padding) }
        return Data(base64Encoded: base64)
    }
}

// MARK: - OAuth helper (PKCE)

@MainActor
public enum GoogleOAuth {
    private static var activePresentationContextProvider: PresentationContextProvider?

    public static func signIn() async throws -> GoogleOAuthTokens {
        // 1) Build PKCE values
        let verifier = randomURLSafeString(length: 64)
        let challenge = codeChallenge(for: verifier)
        let state = randomURLSafeString(length: 32)

        // 2) Build auth URL
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = "accounts.google.com"
        comps.path = "/o/oauth2/v2/auth"
        comps.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: GoogleOAuthConfig.clientID),
            URLQueryItem(name: "redirect_uri", value: GoogleOAuthConfig.redirectURI),
            URLQueryItem(name: "scope", value: GoogleOAuthConfig.scope),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "access_type", value: "offline"), // request refresh token
            URLQueryItem(name: "prompt", value: "consent") // ensure refresh token on subsequent logins
        ]
        guard let authURL = comps.url else { throw OAuthError.invalidURL }

        // 3) Start ASWebAuthenticationSession and wait for callback
        let callbackScheme = GoogleOAuthConfig.redirectScheme
        let callbackURL = try await startWebAuthSession(authURL: authURL, callbackScheme: callbackScheme)

        // 4) Extract code from callback URL
        let code = try parseAuthorizationCallback(callbackURL, expectedState: state)

        // 5) Exchange code for tokens
        let tokens = try await exchangeCodeForTokens(code: code, codeVerifier: verifier)
        return tokens
    }

    // MARK: - Errors
    public enum OAuthError: Error {
        case invalidURL
        case missingCode
        case invalidState
        case authorizationFailed(code: String, description: String?)
        case tokenExchangeFailed(status: Int, body: String?)
        case sessionStartFailed
        case noPresentationAnchor
    }

    // MARK: - Helpers

    private static func startWebAuthSession(authURL: URL, callbackScheme: String) async throws -> URL {
        // Resolve anchor before creating session – never block or crash.
        guard let anchor = resolvePresentationAnchor(from: UIApplication.shared.connectedScenes) else {
            throw OAuthError.noPresentationAnchor
        }

        return try await withCheckedThrowingContinuation { continuation in
            // Hold strong references to avoid deallocation before callback
            var strongSession: ASWebAuthenticationSession?
            var hasResumed = false

            func resumeOnce(_ result: Result<URL, Error>) {
                guard !hasResumed else { return }
                hasResumed = true
                switch result {
                case .success(let url):
                    continuation.resume(returning: url)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            let provider = PresentationContextProvider(anchor: anchor)
            activePresentationContextProvider = provider

            strongSession = ASWebAuthenticationSession(url: authURL, callbackURLScheme: callbackScheme) { url, error in
                defer {
                    strongSession = nil // release after completion
                    activePresentationContextProvider = nil
                }
                if let error {
                    resumeOnce(.failure(error))
                } else if let url {
                    resumeOnce(.success(url))
                } else {
                    resumeOnce(.failure(OAuthError.invalidURL))
                }
            }
            strongSession?.prefersEphemeralWebBrowserSession = true
            strongSession?.presentationContextProvider = provider
            let didStart = strongSession?.start() ?? false
            if !didStart {
                strongSession = nil
                activePresentationContextProvider = nil
                resumeOnce(.failure(OAuthError.sessionStartFailed))
            }
        }
    }

    private static func exchangeCodeForTokens(code: String, codeVerifier: String) async throws -> GoogleOAuthTokens {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        let params: [String: String] = [
            "grant_type": "authorization_code",
            "code": code,
            "code_verifier": codeVerifier,
            "client_id": GoogleOAuthConfig.clientID,
            "redirect_uri": GoogleOAuthConfig.redirectURI
        ]
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formURLEncoded(params).data(using: .utf8)

        let (data, response) = try await GoogleURLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            throw OAuthError.tokenExchangeFailed(status: (response as? HTTPURLResponse)?.statusCode ?? -1, body: body)
        }
        struct TokenResponse: Decodable {
            let access_token: String
            let refresh_token: String?
            let id_token: String?
            let expires_in: Int?
            let scope: String?
        }
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        guard let refresh = decoded.refresh_token else {
            // Google may omit refresh_token on subsequent sign-ins without prompt=consent; treat as failure for our use.
            throw OAuthError.tokenExchangeFailed(status: 200, body: "Missing refresh_token")
        }
        if let grantedScope = decoded.scope {
            let granted = Set(grantedScope.split(whereSeparator: \.isWhitespace).map(String.init))
            let missing = GoogleOAuthConfig.requiredScopes.subtracting(granted)
            if !missing.isEmpty {
                let sortedMissing = missing.sorted().joined(separator: ",")
                throw OAuthError.tokenExchangeFailed(status: 200, body: "Missing granted scopes: \(sortedMissing)")
            }
        }
        return GoogleOAuthTokens(accessToken: decoded.access_token, refreshToken: refresh, idToken: decoded.id_token, expiresIn: decoded.expires_in)
    }

    static func parseAuthorizationCallback(_ callbackURL: URL, expectedState: String) throws -> String {
        let queryItems = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let errorCode = queryItems.first(where: { $0.name == "error" })?.value {
            let description = queryItems
                .first(where: { $0.name == "error_description" })?
                .value?
                .replacingOccurrences(of: "+", with: " ")
            throw OAuthError.authorizationFailed(code: errorCode, description: description)
        }

        let returnedState = queryItems.first(where: { $0.name == "state" })?.value
        guard returnedState == expectedState else {
            throw OAuthError.invalidState
        }

        guard let code = queryItems.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            throw OAuthError.missingCode
        }
        return code
    }

    private static func randomURLSafeString(length: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    private static func codeChallenge(for verifier: String) -> String {
        let data = Data(verifier.utf8)
        let digest = SHA256.hash(data: data)
        let hashed = Data(digest)
        return hashed.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func formURLEncoded(_ params: [String: String]) -> String {
        params
            .sorted { $0.key < $1.key }
            .map { key, value in
                "\(formEncodedComponent(key))=\(formEncodedComponent(value))"
            }
            .joined(separator: "&")
    }

    private static func formEncodedComponent(_ input: String) -> String {
        let hexDigits = Array("0123456789ABCDEF".utf8)
        var output = ""
        output.reserveCapacity(input.utf8.count)

        for byte in input.utf8 {
            switch byte {
            case 0x30...0x39, 0x41...0x5A, 0x61...0x7A, 0x2A, 0x2D, 0x2E, 0x5F:
                output.unicodeScalars.append(UnicodeScalar(byte))
            case 0x20:
                output.append("+")
            default:
                output.append("%")
                output.unicodeScalars.append(UnicodeScalar(hexDigits[Int(byte >> 4)]))
                output.unicodeScalars.append(UnicodeScalar(hexDigits[Int(byte & 0x0F)]))
            }
        }
        return output
    }

    // MARK: - Presentation context provider

    private final class PresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
        let anchor: ASPresentationAnchor

        init(anchor: ASPresentationAnchor) {
            self.anchor = anchor
            super.init()
        }

        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
            anchor
        }
    }

    /// Attempt to find a suitable presentation anchor from the given scenes.
    ///
    /// Returns `nil` when no valid window scene or window is available,
    /// allowing callers to surface a recoverable ``OAuthError/noPresentationAnchor`` error
    /// instead of crashing or blocking the main thread.
    static func resolvePresentationAnchor(from scenes: Set<UIScene>) -> ASPresentationAnchor? {
        let allWindowScenes = scenes.compactMap { $0 as? UIWindowScene }
        guard !allWindowScenes.isEmpty else { return nil }

        let foregroundScenes = allWindowScenes.filter {
            $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive
        }
        let prioritizedScenes = foregroundScenes + allWindowScenes

        for scene in prioritizedScenes {
            if let keyWindow = scene.windows.first(where: \.isKeyWindow) {
                return keyWindow
            }
            if let firstWindow = scene.windows.first {
                return firstWindow
            }
        }

        if let fallbackScene = allWindowScenes.first {
            return ASPresentationAnchor(windowScene: fallbackScene)
        }
        return nil
    }
}

extension GoogleOAuth.OAuthError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "OAuth URL could not be created."
        case .missingCode:
            return "Google did not return an authorization code."
        case .invalidState:
            return "OAuth state validation failed. Please retry sign-in."
        case .authorizationFailed(let code, let description):
            return "Authorization failed (\(code)): \(description ?? "No details")"
        case .tokenExchangeFailed(let status, let body):
            return "Token exchange failed (\(status)): \(body ?? "No details")"
        case .sessionStartFailed:
            return "Could not start the Google sign-in session."
        case .noPresentationAnchor:
            return "No active window available to present Google sign-in. Please try again."
        }
    }
}
