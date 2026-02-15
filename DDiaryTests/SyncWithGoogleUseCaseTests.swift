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

    func test_concurrentSyncRequests_areSerializedAndDoNotDuplicateUploads() async throws {
        let measurements = MockMeasurementsRepository()
        let analytics = MockAnalyticsRepository()
        let google = MockGoogleIntegrationRepository()
        let integration = try await google.getOrCreate()
        integration.isEnabled = true
        integration.spreadsheetId = "sheet123"
        integration.refreshToken = "token"

        let bp = BPMeasurement(timestamp: Date(), systolic: 120, diastolic: 80, pulse: 70, comment: nil)
        try await measurements.insertBP(bp)

        let counter = SyncCallCounter()
        let client = SlowCountingGoogleSheetsClient(counter: counter)
        let sut = SyncWithGoogleUseCase(
            googleIntegrationRepository: google,
            measurementsRepository: measurements,
            analyticsRepository: analytics,
            googleSheetsClient: client
        )

        async let first: Void = sut.syncPendingMeasurements()
        try await Task.sleep(nanoseconds: 20_000_000)
        async let second: Void = sut.syncPendingMeasurements()
        _ = await (first, second)

        let ensureCalls = await counter.ensureCalls()
        let bpUpsertCalls = await counter.bpUpsertCalls()
        let glucoseUpsertCalls = await counter.glucoseUpsertCalls()

        XCTAssertEqual(ensureCalls, 1)
        XCTAssertEqual(bpUpsertCalls, 1)
        XCTAssertEqual(glucoseUpsertCalls, 0)
    }

    func test_progressLifecycle_emitsIncrementalPendingAndFailedCounts() async throws {
        let measurements = MockMeasurementsRepository()
        let analytics = MockAnalyticsRepository()
        let google = MockGoogleIntegrationRepository()
        let integration = try await google.getOrCreate()
        integration.isEnabled = true
        integration.spreadsheetId = "sheet123"
        integration.refreshToken = "token"

        let bp = BPMeasurement(timestamp: Date(), systolic: 120, diastolic: 80, pulse: 70, comment: nil)
        let glucose = GlucoseMeasurement(timestamp: Date(), value: 5.6, unit: .mmolL, measurementType: .beforeMeal, mealSlot: .breakfast, comment: nil)
        try await measurements.insertBP(bp)
        try await measurements.insertGlucose(glucose)

        let snapshotStore = SyncLifecycleSnapshotStore()
        let observer = NotificationCenter.default.addObserver(
            forName: .googleSyncLifecycleChanged,
            object: nil,
            queue: nil
        ) { notification in
            guard
                let rawPhase = notification.userInfo?[GoogleSyncLifecycleUserInfoKey.phase.rawValue] as? String,
                let phase = GoogleSyncLifecyclePhase(rawValue: rawPhase),
                let pending = notification.userInfo?[GoogleSyncLifecycleUserInfoKey.pendingCount.rawValue] as? Int,
                let failed = notification.userInfo?[GoogleSyncLifecycleUserInfoKey.failedCount.rawValue] as? Int
            else {
                return
            }

            switch phase {
            case .progress:
                snapshotStore.appendProgress(pending: pending, failed: failed)
            case .finished:
                snapshotStore.setFinished(pending: pending, failed: failed)
            case .started:
                break
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        let client = RecordingGoogleSheetsClient(mode: .fail(TestError.forced))
        let sut = SyncWithGoogleUseCase(
            googleIntegrationRepository: google,
            measurementsRepository: measurements,
            analyticsRepository: analytics,
            googleSheetsClient: client
        )

        await sut.execute()

        let progressSnapshots = snapshotStore.progressSnapshots()
        let finishedSnapshot = snapshotStore.finishedSnapshot()
        XCTAssertEqual(progressSnapshots.first?.pending, 2)
        XCTAssertEqual(progressSnapshots.first?.failed, 0)
        XCTAssertEqual(progressSnapshots.last?.pending, 0)
        XCTAssertEqual(progressSnapshots.last?.failed, 2)
        XCTAssertEqual(finishedSnapshot?.pending, 0)
        XCTAssertEqual(finishedSnapshot?.failed, 2)
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

private actor SyncCallCounter {
    private var ensure: Int = 0
    private var bpUpserts: Int = 0
    private var glucoseUpserts: Int = 0

    func incrementEnsure() { ensure += 1 }
    func incrementBPUpsert() { bpUpserts += 1 }
    func incrementGlucoseUpsert() { glucoseUpserts += 1 }

    func ensureCalls() -> Int { ensure }
    func bpUpsertCalls() -> Int { bpUpserts }
    func glucoseUpsertCalls() -> Int { glucoseUpserts }
}

private struct SlowCountingGoogleSheetsClient: GoogleSheetsClient, Sendable {
    let counter: SyncCallCounter

    func appendBloodPressureRow(_ row: GoogleSheetsBPRow, credentials: GoogleSheetsCredentials) async throws {}
    func appendGlucoseRow(_ row: GoogleSheetsGlucoseRow, credentials: GoogleSheetsCredentials) async throws {}

    func ensureSheetsAndHeaders(credentials: GoogleSheetsCredentials) async throws {
        await counter.incrementEnsure()
        try await Task.sleep(nanoseconds: 150_000_000)
    }

    func upsertBloodPressureRow(_ row: GoogleSheetsBPRow, credentials: GoogleSheetsCredentials) async throws {
        await counter.incrementBPUpsert()
    }

    func upsertGlucoseRow(_ row: GoogleSheetsGlucoseRow, credentials: GoogleSheetsCredentials) async throws {
        await counter.incrementGlucoseUpsert()
    }
}

private final class SyncLifecycleSnapshotStore: @unchecked Sendable {
    private let lock = NSLock()
    private var progress: [(pending: Int, failed: Int)] = []
    private var finished: (pending: Int, failed: Int)?

    func appendProgress(pending: Int, failed: Int) {
        lock.lock()
        defer { lock.unlock() }
        progress.append((pending: pending, failed: failed))
    }

    func setFinished(pending: Int, failed: Int) {
        lock.lock()
        defer { lock.unlock() }
        finished = (pending: pending, failed: failed)
    }

    func progressSnapshots() -> [(pending: Int, failed: Int)] {
        lock.lock()
        defer { lock.unlock() }
        return progress
    }

    func finishedSnapshot() -> (pending: Int, failed: Int)? {
        lock.lock()
        defer { lock.unlock() }
        return finished
    }
}
