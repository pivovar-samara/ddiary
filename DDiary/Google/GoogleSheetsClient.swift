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
    case decodingError
    case notFound
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
        case .decodingError:
            return "Failed to decode Google Sheets API response."
        case .notFound:
            return "Requested resource was not found."
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

    /// Creates a spreadsheet with BP and Glucose sheets and header rows. Returns spreadsheetId.
    public func createSpreadsheetAndSetup(refreshToken: String, title: String) async throws -> String {
        let access = try await accessToken(using: refreshToken)
        // 1) Create spreadsheet
        let createURL = URL(string: "https://sheets.googleapis.com/v4/spreadsheets")!
        var createReq = URLRequest(url: createURL)
        createReq.httpMethod = "POST"
        createReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        createReq.setValue("Bearer \(access.token)", forHTTPHeaderField: "Authorization")
        struct CreateBody: Encodable { struct Properties: Encodable { let title: String }; let properties: Properties }
        let createBody = CreateBody(properties: .init(title: title))
        createReq.httpBody = try JSONEncoder().encode(createBody)

        do {
            let (data, response) = try await URLSession.shared.data(for: createReq)
            guard let http = response as? HTTPURLResponse else { throw GoogleSheetsClientError.invalidResponse }
            if http.statusCode == 401 {
                // Retry once after refreshing access token again
                let refreshed = try await accessToken(using: refreshToken)
                createReq.setValue("Bearer \(refreshed.token)", forHTTPHeaderField: "Authorization")
                let (data2, response2) = try await URLSession.shared.data(for: createReq)
                guard let http2 = response2 as? HTTPURLResponse, (200..<300).contains(http2.statusCode) else {
                    let body = String(data: data2, encoding: .utf8)
                    throw GoogleSheetsClientError.httpError(statusCode: (response2 as? HTTPURLResponse)?.statusCode ?? -1, body: body)
                }
                let id = try extractSpreadsheetId(from: data2)
                try await ensureSheetsAndHeaders(spreadsheetId: id, bearerToken: refreshed.token)
                return id
            }
            guard (200..<300).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8)
                throw GoogleSheetsClientError.httpError(statusCode: http.statusCode, body: body)
            }
            let id = try extractSpreadsheetId(from: data)
            try await ensureSheetsAndHeaders(spreadsheetId: id, bearerToken: access.token)
            return id
        } catch {
            throw error
        }
    }

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

    public func upsertBloodPressureRow(_ row: GoogleSheetsBPRow, credentials: GoogleSheetsCredentials) async throws {
        try await upsertRow(
            sheetName: SheetNames.bloodPressure,
            rowId: row.id.uuidString,
            values: valuesForBP(row),
            columnCount: 8,
            credentials: credentials
        )
    }

    public func upsertGlucoseRow(_ row: GoogleSheetsGlucoseRow, credentials: GoogleSheetsCredentials) async throws {
        try await upsertRow(
            sheetName: SheetNames.glucose,
            rowId: row.id.uuidString,
            values: valuesForGlucose(row),
            columnCount: 9,
            credentials: credentials
        )
    }

    public func ensureSheetsAndHeaders(credentials: GoogleSheetsCredentials) async throws {
        log("Ensuring sheets/headers for spreadsheetId=\(credentials.spreadsheetId)")
        try await withAccessToken(refreshToken: credentials.refreshToken) { token in
            try await ensureSheetsAndHeaders(spreadsheetId: credentials.spreadsheetId, bearerToken: token)
        }
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

    func buildUpdateRequest(url: URL, bearerToken: String, values: [[String]]) throws -> URLRequest {
        struct UpdateBody: Encodable { let values: [[String]] }
        let body = UpdateBody(values: values)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(body) else {
            throw GoogleSheetsClientError.encodingError
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
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

    func fetchData(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GoogleSheetsClientError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let bodyString = String(data: data, encoding: .utf8)
            throw GoogleSheetsClientError.httpError(statusCode: http.statusCode, body: bodyString)
        }
        return data
    }

    func withAccessToken<T>(refreshToken: String, _ body: @Sendable (String) async throws -> T) async throws -> T {
        do {
            let access = try await accessToken(using: refreshToken)
            return try await body(access.token)
        } catch GoogleSheetsClientError.httpError(let status, _) where status == 401 {
            let refreshed = try await accessToken(using: refreshToken)
            return try await body(refreshed.token)
        }
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

    func upsertRow(
        sheetName: String,
        rowId: String,
        values: [[String]],
        columnCount: Int,
        credentials: GoogleSheetsCredentials
    ) async throws {
        let idColumn = columnLetter(for: columnCount)
        let rowIndex = try await withAccessToken(refreshToken: credentials.refreshToken) { token in
            try await findRowIndex(
                spreadsheetId: credentials.spreadsheetId,
                sheetName: sheetName,
                idColumn: idColumn,
                rowId: rowId,
                bearerToken: token
            )
        }

        if let rowIndex {
            try await withAccessToken(refreshToken: credentials.refreshToken) { token in
                try await updateRow(
                    spreadsheetId: credentials.spreadsheetId,
                    sheetName: sheetName,
                    rowIndex: rowIndex,
                    columnCount: columnCount,
                    values: values,
                    bearerToken: token
                )
            }
        } else {
            let url = try makeAppendRequestURL(spreadsheetId: credentials.spreadsheetId, sheetName: sheetName)
            try await performAppend(url: url, values: values, credentials: credentials)
        }
    }

    func findRowIndex(
        spreadsheetId: String,
        sheetName: String,
        idColumn: String,
        rowId: String,
        bearerToken: String
    ) async throws -> Int? {
        let range = "\(sheetName)!\(idColumn):\(idColumn)"
        let url = URL(string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetId)/values/\(range)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        let data = try await fetchData(request)
        struct ValuesResponse: Decodable { let values: [[String]]? }
        let decoded = try JSONDecoder().decode(ValuesResponse.self, from: data)
        let values = decoded.values ?? []
        for (index, row) in values.enumerated() {
            guard let cell = row.first, !cell.isEmpty else { continue }
            if cell == "id" { continue }
            if cell == rowId {
                return index + 1
            }
        }
        return nil
    }

    func updateRow(
        spreadsheetId: String,
        sheetName: String,
        rowIndex: Int,
        columnCount: Int,
        values: [[String]],
        bearerToken: String
    ) async throws {
        let lastColumn = columnLetter(for: columnCount)
        let range = "\(sheetName)!A\(rowIndex):\(lastColumn)\(rowIndex)"
        var components = URLComponents()
        components.scheme = "https"
        components.host = "sheets.googleapis.com"
        components.path = "/v4/spreadsheets/\(spreadsheetId)/values/\(range)"
        components.queryItems = [URLQueryItem(name: "valueInputOption", value: "USER_ENTERED")]
        guard let url = components.url else { throw GoogleSheetsClientError.invalidURL }
        let request = try buildUpdateRequest(url: url, bearerToken: bearerToken, values: values)
        try await perform(request)
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

    func columnLetter(for index: Int) -> String {
        precondition(index > 0 && index <= 26)
        let scalar = UnicodeScalar(64 + index)!
        return String(Character(scalar))
    }

    // MARK: - Spreadsheet creation helpers

    func extractSpreadsheetId(from data: Data) throws -> String {
        struct Resp: Decodable { let spreadsheetId: String }
        guard let decoded = try? JSONDecoder().decode(Resp.self, from: data) else {
            throw GoogleSheetsClientError.decodingError
        }
        return decoded.spreadsheetId
    }

    /// Ensures two sheets exist (BP, Glucose) and writes header rows.
    func ensureSheetsAndHeaders(spreadsheetId: String, bearerToken: String) async throws {
        try await ensureSheetExists(spreadsheetId: spreadsheetId, bearerToken: bearerToken, title: SheetNames.bloodPressure)
        try await ensureSheetExists(spreadsheetId: spreadsheetId, bearerToken: bearerToken, title: SheetNames.glucose)
        try await ensureHeaderRow(
            spreadsheetId: spreadsheetId,
            sheetName: SheetNames.bloodPressure,
            headers: ["timestamp","date","time","systolic","diastolic","pulse","comment","id"],
            bearerToken: bearerToken
        )
        try await ensureHeaderRow(
            spreadsheetId: spreadsheetId,
            sheetName: SheetNames.glucose,
            headers: ["timestamp","date","time","value","unit","measurementType","mealSlot","comment","id"],
            bearerToken: bearerToken
        )
    }

    func ensureSheetExists(spreadsheetId: String, bearerToken: String, title: String) async throws {
        // Get spreadsheet and check if sheet exists
        let getURL = URL(string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetId)?fields=sheets(properties(title))")!
        var getReq = URLRequest(url: getURL)
        getReq.httpMethod = "GET"
        getReq.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: getReq)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            throw GoogleSheetsClientError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1, body: body)
        }
        struct GetResp: Decodable { struct Sheet: Decodable { struct Props: Decodable { let title: String }; let properties: Props }; let sheets: [Sheet]? }
        let decoded = try JSONDecoder().decode(GetResp.self, from: data)
        let titles = (decoded.sheets ?? []).map { $0.properties.title }
        guard !titles.contains(title) else { return }
        // Add sheet via batchUpdate
        let batchURL = URL(string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetId):batchUpdate")!
        var batchReq = URLRequest(url: batchURL)
        batchReq.httpMethod = "POST"
        batchReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        batchReq.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        struct AddSheetBody: Encodable { struct Request: Encodable { struct AddSheet: Encodable { struct Properties: Encodable { let title: String }; let properties: Properties }; let addSheet: AddSheet? }; let requests: [Request] }
        let body = AddSheetBody(requests: [.init(addSheet: .init(properties: .init(title: title)))])
        batchReq.httpBody = try JSONEncoder().encode(body)
        let (bdata, bresp) = try await URLSession.shared.data(for: batchReq)
        guard let bhttp = bresp as? HTTPURLResponse, (200..<300).contains(bhttp.statusCode) else {
            let bodyStr = String(data: bdata, encoding: .utf8)
            throw GoogleSheetsClientError.httpError(statusCode: (bresp as? HTTPURLResponse)?.statusCode ?? -1, body: bodyStr)
        }
    }

    func ensureHeaderRow(
        spreadsheetId: String,
        sheetName: String,
        headers: [String],
        bearerToken: String
    ) async throws {
        let lastColumn = columnLetter(for: headers.count)
        let range = "\(sheetName)!A1:\(lastColumn)1"
        let url = URL(string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetId)/values/\(range)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        let data = try await fetchData(request)
        struct ValuesResponse: Decodable { let values: [[String]]? }
        let decoded = try JSONDecoder().decode(ValuesResponse.self, from: data)
        if let row = decoded.values?.first, row == headers {
            log("Headers already present for \(sheetName)")
            return
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "sheets.googleapis.com"
        components.path = "/v4/spreadsheets/\(spreadsheetId)/values/\(range)"
        components.queryItems = [URLQueryItem(name: "valueInputOption", value: "USER_ENTERED")]
        guard let updateURL = components.url else { throw GoogleSheetsClientError.invalidURL }
        let updateRequest = try buildUpdateRequest(url: updateURL, bearerToken: bearerToken, values: [headers])
        try await perform(updateRequest)
        log("Header row written for \(sheetName)")
    }

    func log(_ message: String) {
        #if DEBUG
        print("[GoogleSheets] \(message)")
        #endif
    }
}

private extension ISO8601DateFormatter {
    static let sharedWithFractionalSeconds: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
