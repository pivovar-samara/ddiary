import XCTest
@testable import DDiary

@MainActor
final class UpdateBPMeasurementUseCaseTests: XCTestCase {
    func test_happyPath_updatesMeasurement_schedulesSync_andLogsAnalytics() async throws {
        let repo = MockMeasurementsRepository()
        let analytics = MockAnalyticsRepository()
        var syncScheduleCount = 0
        let sut = UpdateBPMeasurementUseCase(
            measurementsRepository: repo,
            analyticsRepository: analytics,
            scheduleGoogleSyncIfConnected: { syncScheduleCount += 1 }
        )

        let measurement = BPMeasurement(
            id: UUID(),
            timestamp: Date(),
            systolic: 120,
            diastolic: 80,
            pulse: 70,
            comment: "old",
            googleSyncStatus: .success,
            googleLastError: "old error",
            googleLastSyncAt: Date()
        )
        try await repo.insertBP(measurement)

        try await sut.execute(
            measurement: measurement,
            systolic: 130,
            diastolic: 85,
            pulse: 72,
            comment: nil
        )

        let updatedMaybe = try await repo.bpMeasurement(id: measurement.id)
        let updated = try XCTUnwrap(updatedMaybe)
        XCTAssertEqual(updated.systolic, 130)
        XCTAssertEqual(updated.diastolic, 85)
        XCTAssertEqual(updated.pulse, 72)
        XCTAssertNil(updated.comment)
        XCTAssertEqual(updated.googleSyncStatus, .pending)
        XCTAssertNil(updated.googleLastError)
        XCTAssertEqual(syncScheduleCount, 1)
        XCTAssertEqual(analytics.measurementLogged, [.bloodPressure])
    }

    func test_errorPath_repositoryThrows_doesNotScheduleSync() async throws {
        @MainActor
        final class ThrowingUpdateBPRepo: MeasurementsRepository {
            let base = MockMeasurementsRepository()

            func insertBP(_ measurement: BPMeasurement) async throws { try await base.insertBP(measurement) }
            func updateBP(_ measurement: BPMeasurement) async throws { throw TestError.forced }
            func deleteBP(_ measurement: BPMeasurement) async throws { try await base.deleteBP(measurement) }
            func bpMeasurement(id: UUID) async throws -> BPMeasurement? { try await base.bpMeasurement(id: id) }
            func bpMeasurements(from: Date, to: Date) async throws -> [BPMeasurement] {
                try await base.bpMeasurements(from: from, to: to)
            }
            func pendingOrFailedBPSync() async throws -> [BPMeasurement] { try await base.pendingOrFailedBPSync() }
            func insertGlucose(_ measurement: GlucoseMeasurement) async throws { try await base.insertGlucose(measurement) }
            func updateGlucose(_ measurement: GlucoseMeasurement) async throws { try await base.updateGlucose(measurement) }
            func deleteGlucose(_ measurement: GlucoseMeasurement) async throws { try await base.deleteGlucose(measurement) }
            func glucoseMeasurement(id: UUID) async throws -> GlucoseMeasurement? { try await base.glucoseMeasurement(id: id) }
            func glucoseMeasurements(from: Date, to: Date) async throws -> [GlucoseMeasurement] {
                try await base.glucoseMeasurements(from: from, to: to)
            }
            func pendingOrFailedGlucoseSync() async throws -> [GlucoseMeasurement] {
                try await base.pendingOrFailedGlucoseSync()
            }
        }

        let repo = ThrowingUpdateBPRepo()
        let analytics = MockAnalyticsRepository()
        var syncScheduleCount = 0
        let sut = UpdateBPMeasurementUseCase(
            measurementsRepository: repo,
            analyticsRepository: analytics,
            scheduleGoogleSyncIfConnected: { syncScheduleCount += 1 }
        )

        let measurement = BPMeasurement(
            id: UUID(),
            timestamp: Date(),
            systolic: 120,
            diastolic: 80,
            pulse: 70,
            comment: "old"
        )
        try await repo.insertBP(measurement)

        do {
            try await sut.execute(
                measurement: measurement,
                systolic: 130,
                diastolic: 85,
                pulse: 72,
                comment: nil
            )
            XCTFail("Expected error to be thrown")
        } catch {
            // expected
        }

        XCTAssertEqual(syncScheduleCount, 0)
        XCTAssertEqual(analytics.measurementLogged, [])
        XCTAssertEqual(analytics.measurementSaveFailed.count, 1)
        XCTAssertEqual(analytics.measurementSaveFailed.first?.kind, .bloodPressure)
    }
}
