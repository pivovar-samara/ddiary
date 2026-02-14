import Foundation
import AuthenticationServices
import CryptoKit
import UIKit
import Security

// MARK: - Configuration

/// Configure these values for your Google OAuth client.
/// - Note: You must register your bundle's redirect URI scheme in your Info.plist (URL Types).
public enum GoogleOAuthConfig {
    /// Your OAuth 2.0 Client ID from Google Cloud Console (iOS type or Web type depending on flow).
    public static var clientID: String {
        Bundle.main.object(forInfoDictionaryKey: "GOOGLE_OAUTH_KEY") as? String ?? ""
    }
    /// The full redirect URI registered with Google, e.g., "ddiary:/goauth".
    public static var redirectURI: String = "com.googleusercontent.apps.383781347842-eebk0q5ogjta4s85tel3dccfd8u2fj1o:/oauthredirect"
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
    /// Space-separated scopes. Include Sheets, and optionally OpenID/email for user id.
    public static var scope: String = "openid email profile https://www.googleapis.com/auth/spreadsheets"
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
    private static var fallbackPresentationAnchor: ASPresentationAnchor?

    public static func signIn() async throws -> GoogleOAuthTokens {
        // 1) Build PKCE values
        let verifier = randomURLSafeString(length: 64)
        let challenge = codeChallenge(for: verifier)

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
            URLQueryItem(name: "access_type", value: "offline"), // request refresh token
            URLQueryItem(name: "prompt", value: "consent") // ensure refresh token on subsequent logins
        ]
        guard let authURL = comps.url else { throw OAuthError.invalidURL }

        // 3) Start ASWebAuthenticationSession and wait for callback
        let callbackScheme = GoogleOAuthConfig.redirectScheme
        let callbackURL = try await startWebAuthSession(authURL: authURL, callbackScheme: callbackScheme)

        // 4) Extract code from callback URL
        guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw OAuthError.missingCode
        }

        // 5) Exchange code for tokens
        let tokens = try await exchangeCodeForTokens(code: code, codeVerifier: verifier)
        return tokens
    }

    // MARK: - Errors
    public enum OAuthError: Error {
        case invalidURL
        case missingCode
        case tokenExchangeFailed(status: Int, body: String?)
        case sessionStartFailed
    }

    // MARK: - Helpers

    private static func startWebAuthSession(authURL: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
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

            if fallbackPresentationAnchor == nil,
               let preResolvedAnchor = resolvePresentationAnchor(from: UIApplication.shared.connectedScenes) {
                fallbackPresentationAnchor = preResolvedAnchor
            }

            guard fallbackPresentationAnchor != nil else {
                resumeOnce(.failure(OAuthError.sessionStartFailed))
                return
            }

            let provider = PresentationContextProvider()
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

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            throw OAuthError.tokenExchangeFailed(status: (response as? HTTPURLResponse)?.statusCode ?? -1, body: body)
        }
        struct TokenResponse: Decodable { let access_token: String; let refresh_token: String?; let id_token: String?; let expires_in: Int? }
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        guard let refresh = decoded.refresh_token else {
            // Google may omit refresh_token on subsequent sign-ins without prompt=consent; treat as failure for our use.
            throw OAuthError.tokenExchangeFailed(status: 200, body: "Missing refresh_token")
        }
        return GoogleOAuthTokens(accessToken: decoded.access_token, refreshToken: refresh, idToken: decoded.id_token, expiresIn: decoded.expires_in)
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
        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
            GoogleOAuth.presentationAnchor(from: UIApplication.shared.connectedScenes)
        }
    }

    static func presentationAnchor(from scenes: Set<UIScene>) -> ASPresentationAnchor {
        if let anchor = resolvePresentationAnchor(from: scenes) {
            return anchor
        }
        if let anchor = resolvePresentationAnchor(from: UIApplication.shared.connectedScenes) {
            return anchor
        }
        if let fallbackPresentationAnchor {
            return fallbackPresentationAnchor
        }

        // Last-resort fallback for transient app states.
        if let fallbackScene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            let fallback = ASPresentationAnchor(windowScene: fallbackScene)
            fallback.rootViewController = UIViewController()
            fallbackPresentationAnchor = fallback
            return fallback
        }

        assertionFailure("No UIWindowScene available for ASWebAuthenticationSession presentation anchor.")
        if let fallbackPresentationAnchor {
            return fallbackPresentationAnchor
        }

        // Prefer waiting briefly over terminating in transient lifecycle races.
        while true {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            if let recoveredAnchor = resolvePresentationAnchor(from: UIApplication.shared.connectedScenes) {
                fallbackPresentationAnchor = recoveredAnchor
                return recoveredAnchor
            }
        }
    }

    private static func resolvePresentationAnchor(from scenes: Set<UIScene>) -> ASPresentationAnchor? {
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
