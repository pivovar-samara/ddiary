import Foundation

/// A simple no-op GoogleSheetsClient implementation for local development and previews.
struct NoopGoogleSheetsClient: GoogleSheetsClient, Sendable {
    func appendBloodPressureRow(_ row: GoogleSheetsBPRow, credentials: GoogleSheetsCredentials) async throws {
        // No-op: pretend success
    }

    func appendGlucoseRow(_ row: GoogleSheetsGlucoseRow, credentials: GoogleSheetsCredentials) async throws {
        // No-op: pretend success
    }
}
