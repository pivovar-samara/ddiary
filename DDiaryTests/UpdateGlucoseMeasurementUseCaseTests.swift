import XCTest
@testable import DDiary

@MainActor
final class UpdateGlucoseMeasurementUseCaseTests: XCTestCase {
    func test_happyPath_updatesMeasurement_schedulesSync_andLogsAnalytics() async throws {
        let repo = MockMeasurementsRepository()
        let analytics = MockAnalyticsRepository()
        var syncScheduleCount = 0
        let sut = UpdateGlucoseMeasurementUseCase(
            measurementsRepository: repo,
            analyticsRepository: analytics,
            scheduleGoogleSyncIfConnected: { syncScheduleCount += 1 }
        )

        let measurement = GlucoseMeasurement(
            id: UUID(),
            timestamp: Date(),
            value: 5.4,
            unit: .mmolL,
            measurementType: .beforeMeal,
            mealSlot: .breakfast,
            comment: "old",
            googleSyncStatus: .success,
            googleLastError: "old error",
            googleLastSyncAt: Date()
        )
        try await repo.insertGlucose(measurement)

        try await sut.execute(
            measurement: measurement,
            value: 6.1,
            unit: .mmolL,
            measurementType: .afterMeal2h,
            mealSlot: .lunch,
            comment: nil
        )

        let updatedMaybe = try await repo.glucoseMeasurement(id: measurement.id)
        let updated = try XCTUnwrap(updatedMaybe)
        XCTAssertEqual(updated.value, 6.1)
        XCTAssertEqual(updated.unit, .mmolL)
        XCTAssertEqual(updated.measurementType, .afterMeal2h)
        XCTAssertEqual(updated.mealSlot, .lunch)
        XCTAssertNil(updated.comment)
        XCTAssertEqual(updated.googleSyncStatus, .pending)
        XCTAssertNil(updated.googleLastError)
        XCTAssertEqual(syncScheduleCount, 1)
        XCTAssertEqual(analytics.measurementLogged, [.glucose])
    }

    func test_errorPath_repositoryThrows_doesNotScheduleSync() async throws {
        @MainActor
        final class ThrowingUpdateGlucoseRepo: MeasurementsRepository {
            let base = MockMeasurementsRepository()

            func insertBP(_ measurement: BPMeasurement) async throws { try await base.insertBP(measurement) }
            func updateBP(_ measurement: BPMeasurement) async throws { try await base.updateBP(measurement) }
            func deleteBP(_ measurement: BPMeasurement) async throws { try await base.deleteBP(measurement) }
            func bpMeasurement(id: UUID) async throws -> BPMeasurement? { try await base.bpMeasurement(id: id) }
            func bpMeasurements(from: Date, to: Date) async throws -> [BPMeasurement] {
                try await base.bpMeasurements(from: from, to: to)
            }
            func pendingOrFailedBPSync() async throws -> [BPMeasurement] { try await base.pendingOrFailedBPSync() }
            func insertGlucose(_ measurement: GlucoseMeasurement) async throws { try await base.insertGlucose(measurement) }
            func updateGlucose(_ measurement: GlucoseMeasurement) async throws { throw TestError.forced }
            func deleteGlucose(_ measurement: GlucoseMeasurement) async throws { try await base.deleteGlucose(measurement) }
            func glucoseMeasurement(id: UUID) async throws -> GlucoseMeasurement? { try await base.glucoseMeasurement(id: id) }
            func glucoseMeasurements(from: Date, to: Date) async throws -> [GlucoseMeasurement] {
                try await base.glucoseMeasurements(from: from, to: to)
            }
            func pendingOrFailedGlucoseSync() async throws -> [GlucoseMeasurement] {
                try await base.pendingOrFailedGlucoseSync()
            }
        }

        let repo = ThrowingUpdateGlucoseRepo()
        let analytics = MockAnalyticsRepository()
        var syncScheduleCount = 0
        let sut = UpdateGlucoseMeasurementUseCase(
            measurementsRepository: repo,
            analyticsRepository: analytics,
            scheduleGoogleSyncIfConnected: { syncScheduleCount += 1 }
        )

        let measurement = GlucoseMeasurement(
            id: UUID(),
            timestamp: Date(),
            value: 5.4,
            unit: .mmolL,
            measurementType: .beforeMeal,
            mealSlot: .breakfast,
            comment: "old"
        )
        try await repo.insertGlucose(measurement)

        do {
            try await sut.execute(
                measurement: measurement,
                value: 6.1,
                unit: .mmolL,
                measurementType: .afterMeal2h,
                mealSlot: .lunch,
                comment: nil
            )
            XCTFail("Expected error to be thrown")
        } catch {
            // expected
        }

        XCTAssertEqual(syncScheduleCount, 0)
        XCTAssertEqual(analytics.measurementLogged, [])
        XCTAssertEqual(analytics.measurementSaveFailed.count, 1)
        XCTAssertEqual(analytics.measurementSaveFailed.first?.kind, .glucose)
    }
}
