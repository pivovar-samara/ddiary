//  GoogleSheetsClient.swift
//  DDiary
//
//  Live implementation for the existing GoogleSheetsClient protocol declared
//  in RepositoryProtocols.swift. This client is Sendable and operates on
//  Sendable DTOs (GoogleSheetsBPRow, GoogleSheetsGlucoseRow, GoogleSheetsCredentials).
//  It uses async/await URLSession calls and includes real token refresh with 401 retry.

import Foundation

// MARK: - Errors

public enum GoogleSheetsClientError: Error, LocalizedError, Sendable {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, body: String?)
    case encodingError
    case tokenRefreshFailed

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid Google Sheets API URL."
        case .invalidResponse:
            return "Invalid response from Google Sheets API."
        case .httpError(let status, let body):
            return "HTTP error (\(status)). Body: \(body ?? "<none>")"
        case .encodingError:
            return "Failed to encode request payload."
        case .tokenRefreshFailed:
            return "Failed to refresh Google access token."
        }
    }
}

// MARK: - Token update center

actor GoogleTokenUpdateCenter {
    static let shared = GoogleTokenUpdateCenter()

    private var onRefreshTokenUpdated: (@Sendable (String) async -> Void)?

    func configure(onRefreshTokenUpdated: (@Sendable (String) async -> Void)?) {
        self.onRefreshTokenUpdated = onRefreshTokenUpdated
    }

    func persist(newRefreshToken: String) async {
        guard let handler = onRefreshTokenUpdated else { return }
        await handler(newRefreshToken)
    }
}

public enum LiveGoogleSheetsClientConfig {
    /// Configure a global handler to persist a new refresh token when Google returns a rotated token.
    /// Call this once during app setup (e.g., in AppContainer init).
    public static func configureTokenPersistence(onRefreshTokenUpdated: (@Sendable (String) async -> Void)?) {
        Task { await GoogleTokenUpdateCenter.shared.configure(onRefreshTokenUpdated: onRefreshTokenUpdated) }
    }
}

// MARK: - Live client

public struct LiveGoogleSheetsClient: GoogleSheetsClient, Sendable {
    public init() {}

    public func appendBloodPressureRow(_ row: GoogleSheetsBPRow, credentials: GoogleSheetsCredentials) async throws {
        let url = try makeAppendRequestURL(spreadsheetId: credentials.spreadsheetId, sheetName: SheetNames.bloodPressure)
        let values = valuesForBP(row)
        try await performAppend(url: url, values: values, credentials: credentials)
    }

    public func appendGlucoseRow(_ row: GoogleSheetsGlucoseRow, credentials: GoogleSheetsCredentials) async throws {
        let url = try makeAppendRequestURL(spreadsheetId: credentials.spreadsheetId, sheetName: SheetNames.glucose)
        let values = valuesForGlucose(row)
        try await performAppend(url: url, values: values, credentials: credentials)
    }

    // MARK: - Core append with 401 retry
    private func performAppend(url: URL, values: [[String]], credentials: GoogleSheetsCredentials) async throws {
        // First attempt with current refresh token
        var access = try await accessToken(using: credentials.refreshToken)
        var request = try buildAppendRequest(url: url, bearerToken: access.token, values: values)
        do {
            try await perform(request)
            return
        } catch GoogleSheetsClientError.httpError(let status, _) where status == 401 {
            // Retry: refresh access token again (in case of near-expiry), and try once more
            access = try await accessToken(using: credentials.refreshToken)
            request = try buildAppendRequest(url: url, bearerToken: access.token, values: values)
            try await perform(request)
            return
        } catch {
            throw error
        }
    }
}

// MARK: - Constants

private enum SheetNames {
    static let bloodPressure = "BP"        // Aligned with README
    static let glucose = "Glucose"        // Aligned with README
}

// MARK: - Private helpers

private extension LiveGoogleSheetsClient {
    struct AccessToken: Sendable { let token: String }

    func makeAppendRequestURL(spreadsheetId: String, sheetName: String) throws -> URL {
        // Google Sheets API v4 append endpoint
        var components = URLComponents()
        components.scheme = "https"
        components.host = "sheets.googleapis.com"
        components.path = "/v4/spreadsheets/\(spreadsheetId)/values/\(sheetName):append"
        components.queryItems = [
            URLQueryItem(name: "valueInputOption", value: "USER_ENTERED"),
            URLQueryItem(name: "insertDataOption", value: "INSERT_ROWS")
        ]
        guard let url = components.url else { throw GoogleSheetsClientError.invalidURL }
        return url
    }

    func buildAppendRequest(url: URL, bearerToken: String, values: [[String]]) throws -> URLRequest {
        struct AppendBody: Encodable { let values: [[String]]; let majorDimension: String }
        let body = AppendBody(values: values, majorDimension: "ROWS")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(body) else {
            throw GoogleSheetsClientError.encodingError
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = data
        return request
    }

    func perform(_ request: URLRequest) async throws {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GoogleSheetsClientError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let bodyString = String(data: data, encoding: .utf8)
            throw GoogleSheetsClientError.httpError(statusCode: http.statusCode, body: bodyString)
        }
        // Optionally decode response (e.g., updatedRange). Not required for minimal client.
    }

    /// Exchange a refresh token for an access token. If Google returns a new refresh_token, persist it.
    func accessToken(using refreshToken: String) async throws -> AccessToken {
        guard !refreshToken.isEmpty else { throw GoogleSheetsClientError.tokenRefreshFailed }
        let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!
        let comps = URLComponents(url: tokenURL, resolvingAgainstBaseURL: false)!
        var request = URLRequest(url: comps.url!)
        request.httpMethod = "POST"
        let params: [String: String] = [
            "grant_type": "refresh_token",
            "client_id": GoogleOAuthConfig.clientID,
            "refresh_token": refreshToken
        ]
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formURLEncoded(params).data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            throw GoogleSheetsClientError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1, body: body)
        }

        struct TokenResponse: Decodable { let access_token: String; let expires_in: Int?; let refresh_token: String? }
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)

        if let newRT = decoded.refresh_token, newRT != refreshToken {
            // Persist rotated refresh token
            await GoogleTokenUpdateCenter.shared.persist(newRefreshToken: newRT)
        }
        return AccessToken(token: decoded.access_token)
    }

    func formURLEncoded(_ params: [String: String]) -> String {
        params.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            return "\(k)=\(v)"
        }.joined(separator: "&")
    }

    func valuesForBP(_ row: GoogleSheetsBPRow) -> [[String]] {
        let iso = iso8601String(from: row.timestamp)
        let dateStr = dateString(from: row.timestamp)
        let timeStr = timeString(from: row.timestamp)
        let systolic = String(row.systolic)
        let diastolic = String(row.diastolic)
        let pulse = String(row.pulse)
        let comment = row.comment ?? ""
        return [[iso, dateStr, timeStr, systolic, diastolic, pulse, comment, row.id.uuidString]]
    }

    func valuesForGlucose(_ row: GoogleSheetsGlucoseRow) -> [[String]] {
        let iso = iso8601String(from: row.timestamp)
        let dateStr = dateString(from: row.timestamp)
        let timeStr = timeString(from: row.timestamp)
        let value = String(format: "%.3f", row.value)
        let unit = row.unit.rawValue
        let type = row.measurementType.rawValue
        let meal = row.mealSlot.rawValue
        let comment = row.comment ?? ""
        return [[iso, dateStr, timeStr, value, unit, type, meal, comment, row.id.uuidString]]
    }

    func iso8601String(from date: Date) -> String {
        ISO8601DateFormatter.sharedWithFractionalSeconds.string(from: date)
    }

    func dateString(from date: Date) -> String {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: date)
    }

    func timeString(from date: Date) -> String {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "HH:mm"
        return df.string(from: date)
    }
}

private extension ISO8601DateFormatter {
    static let sharedWithFractionalSeconds: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
