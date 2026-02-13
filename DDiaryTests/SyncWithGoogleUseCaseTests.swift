//
//  SyncWithGoogleUseCaseTests.swift
//  DDiary
//
//  Created by Ilia Khokhlov on 10.12.25.
//

import XCTest
@testable import DDiary

@MainActor
final class SyncWithGoogleUseCaseTests: XCTestCase {
    func test_happyPath_syncsPendingAndMarksSuccess() async throws {
        // Repos
        let measurements = MockMeasurementsRepository()
        let analytics = MockAnalyticsRepository()
        let google = MockGoogleIntegrationRepository()
        // Enable integration
        let integration = try await google.getOrCreate()
        integration.isEnabled = true
        integration.spreadsheetId = "sheet123"
        integration.refreshToken = "token"

        // Seed pending data
        let bp = BPMeasurement(timestamp: Date(), systolic: 120, diastolic: 80, pulse: 70, comment: nil)
        let gl = GlucoseMeasurement(timestamp: Date(), value: 5.6, unit: .mmolL, measurementType: .beforeMeal, mealSlot: .breakfast, comment: nil)
        try await measurements.insertBP(bp)
        try await measurements.insertGlucose(gl)

        let client = RecordingGoogleSheetsClient(mode: .succeed)
        let sut = SyncWithGoogleUseCase(googleIntegrationRepository: google, measurementsRepository: measurements, analyticsRepository: analytics, googleSheetsClient: client)

        await sut.execute()

        let syncedBP = try await measurements.bpMeasurement(id: bp.id)
        let syncedGl = try await measurements.glucoseMeasurement(id: gl.id)
        XCTAssertEqual(syncedBP?.googleSyncStatus, .success)
        XCTAssertEqual(syncedGl?.googleSyncStatus, .success)
        XCTAssertGreaterThan(analytics.googleSyncSuccessCount, 0)
    }

    func test_errorPath_integrationDisabled_noCrash_noChanges() async throws {
        let measurements = MockMeasurementsRepository()
        let analytics = MockAnalyticsRepository()
        let google = MockGoogleIntegrationRepository()
        // Integration default is disabled

        let bp = BPMeasurement(timestamp: Date(), systolic: 120, diastolic: 80, pulse: 70, comment: nil)
        try await measurements.insertBP(bp)

        let client = RecordingGoogleSheetsClient(mode: .succeed)
        let sut = SyncWithGoogleUseCase(googleIntegrationRepository: google, measurementsRepository: measurements, analyticsRepository: analytics, googleSheetsClient: client)

        await sut.execute()

        let unchanged = try await measurements.bpMeasurement(id: bp.id)
        XCTAssertEqual(unchanged?.googleSyncStatus, .pending)
        XCTAssertFalse(analytics.googleSyncFailureReasons.isEmpty)
    }

    func test_errorPath_clientFails_marksFailed() async throws {
        let measurements = MockMeasurementsRepository()
        let analytics = MockAnalyticsRepository()
        let google = MockGoogleIntegrationRepository()
        let integration = try await google.getOrCreate()
        integration.isEnabled = true
        integration.spreadsheetId = "sheet123"
        integration.refreshToken = "token"

        let bp = BPMeasurement(timestamp: Date(), systolic: 120, diastolic: 80, pulse: 70, comment: nil)
        try await measurements.insertBP(bp)

        let client = RecordingGoogleSheetsClient(mode: .fail(TestError.forced))
        let sut = SyncWithGoogleUseCase(googleIntegrationRepository: google, measurementsRepository: measurements, analyticsRepository: analytics, googleSheetsClient: client)

        await sut.execute()

        let updated = try await measurements.bpMeasurement(id: bp.id)
        XCTAssertEqual(updated?.googleSyncStatus, .failed)
        XCTAssertFalse(analytics.googleSyncFailureReasons.isEmpty)
    }

    func test_invalidGrant_disablesIntegrationAndKeepsPendingMeasurements() async throws {
        let measurements = MockMeasurementsRepository()
        let analytics = MockAnalyticsRepository()
        let google = MockGoogleIntegrationRepository()
        let integration = try await google.getOrCreate()
        integration.isEnabled = true
        integration.spreadsheetId = "sheet123"
        integration.refreshToken = "token"
        integration.googleUserId = "user@example.com"

        let bp = BPMeasurement(timestamp: Date(), systolic: 120, diastolic: 80, pulse: 70, comment: nil)
        try await measurements.insertBP(bp)

        let client = InvalidGrantGoogleSheetsClient()
        let sut = SyncWithGoogleUseCase(googleIntegrationRepository: google, measurementsRepository: measurements, analyticsRepository: analytics, googleSheetsClient: client)

        await sut.execute()

        XCTAssertFalse(integration.isEnabled)
        XCTAssertNil(integration.refreshToken)
        XCTAssertEqual(integration.spreadsheetId, "sheet123")
        XCTAssertEqual(integration.googleUserId, "user@example.com")

        let unchanged = try await measurements.bpMeasurement(id: bp.id)
        XCTAssertEqual(unchanged?.googleSyncStatus, .pending)
        XCTAssertTrue(analytics.googleSyncFailureReasons.contains { $0 == "google_invalid_grant" })
    }
}

private struct InvalidGrantGoogleSheetsClient: GoogleSheetsClient, Sendable {
    func appendBloodPressureRow(_ row: GoogleSheetsBPRow, credentials: GoogleSheetsCredentials) async throws {}
    func appendGlucoseRow(_ row: GoogleSheetsGlucoseRow, credentials: GoogleSheetsCredentials) async throws {}

    func ensureSheetsAndHeaders(credentials: GoogleSheetsCredentials) async throws {
        throw GoogleSheetsClientError.httpError(
            statusCode: 400,
            body: """
            {
              "error": "invalid_grant",
              "error_description": "Token has been expired or revoked."
            }
            """
        )
    }
}
