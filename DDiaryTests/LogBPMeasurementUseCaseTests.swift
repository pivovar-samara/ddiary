//
//  LogBPMeasurementUseCaseTests.swift
//  DDiary
//
//  Created by Ilia Khokhlov on 10.12.25.
//

import XCTest
@testable import DDiary

@MainActor
final class LogBPMeasurementUseCaseTests: XCTestCase {
    func test_happyPath_insertsAndLogsAnalytics() async throws {
        let repo = MockMeasurementsRepository()
        let analytics = MockAnalyticsRepository()
        var syncScheduleCount = 0
        let sut = LogBPMeasurementUseCase(
            measurementsRepository: repo,
            analyticsRepository: analytics,
            scheduleGoogleSyncIfConnected: { syncScheduleCount += 1 }
        )

        try await sut.execute(systolic: 120, diastolic: 80, pulse: 70, comment: "ok")

        // Verify a single BP exists with pending sync
        let all = try await repo.bpMeasurements(from: Date.distantPast, to: Date.distantFuture)
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.googleSyncStatus, .pending)
        // Analytics called
        XCTAssertEqual(analytics.measurementLogged, [.bloodPressure])
        XCTAssertEqual(syncScheduleCount, 1)
    }

    func test_errorPath_repositoryThrows() async throws {
        @MainActor
        final class ThrowingInsertBPRepo: MeasurementsRepository {
            let base = MockMeasurementsRepository()
            func insertBP(_ measurement: BPMeasurement) async throws { throw TestError.forced }
            func updateBP(_ measurement: BPMeasurement) async throws { try await base.updateBP(measurement) }
            func deleteBP(_ measurement: BPMeasurement) async throws { try await base.deleteBP(measurement) }
            func bpMeasurement(id: UUID) async throws -> BPMeasurement? { try await base.bpMeasurement(id: id) }
            func bpMeasurements(from: Date, to: Date) async throws -> [BPMeasurement] { try await base.bpMeasurements(from: from, to: to) }
            func pendingOrFailedBPSync() async throws -> [BPMeasurement] { try await base.pendingOrFailedBPSync() }
            func insertGlucose(_ measurement: GlucoseMeasurement) async throws { try await base.insertGlucose(measurement) }
            func updateGlucose(_ measurement: GlucoseMeasurement) async throws { try await base.updateGlucose(measurement) }
            func deleteGlucose(_ measurement: GlucoseMeasurement) async throws { try await base.deleteGlucose(measurement) }
            func glucoseMeasurement(id: UUID) async throws -> GlucoseMeasurement? { try await base.glucoseMeasurement(id: id) }
            func glucoseMeasurements(from: Date, to: Date) async throws -> [GlucoseMeasurement] { try await base.glucoseMeasurements(from: from, to: to) }
            func pendingOrFailedGlucoseSync() async throws -> [GlucoseMeasurement] { try await base.pendingOrFailedGlucoseSync() }
        }
        let repo = ThrowingInsertBPRepo()
        let analytics = MockAnalyticsRepository()
        var syncScheduleCount = 0
        let sut = LogBPMeasurementUseCase(
            measurementsRepository: repo,
            analyticsRepository: analytics,
            scheduleGoogleSyncIfConnected: { syncScheduleCount += 1 }
        )

        await XCTAssertThrowsErrorAsync(try await sut.execute(systolic: 120, diastolic: 80, pulse: 70, comment: nil))
        // Ensure nothing inserted
        let all = try await repo.bpMeasurements(from: Date.distantPast, to: Date.distantFuture)
        XCTAssertTrue(all.isEmpty)
        // Analytics should not record success
        XCTAssertTrue(analytics.measurementLogged.isEmpty)
        XCTAssertEqual(analytics.measurementSaveFailed.count, 1)
        XCTAssertEqual(analytics.measurementSaveFailed.first?.kind, .bloodPressure)
        XCTAssertEqual(syncScheduleCount, 0)
    }

    func test_concurrentCalls_doNotCrash() async throws {
        let repo = MockMeasurementsRepository()
        let analytics = MockAnalyticsRepository()
        let sut = LogBPMeasurementUseCase(measurementsRepository: repo, analyticsRepository: analytics)

        async let t1: Void = sut.execute(systolic: 110, diastolic: 70, pulse: 60, comment: nil)
        async let t2: Void = sut.execute(systolic: 115, diastolic: 75, pulse: 65, comment: nil)
        _ = try await (t1, t2)

        let all = try await repo.bpMeasurements(from: Date.distantPast, to: Date.distantFuture)
        XCTAssertEqual(all.count, 2)
    }

    func test_withPlannedScheduledDate_cancelsPlannedNotification() async throws {
        let repo = MockMeasurementsRepository()
        let analytics = MockAnalyticsRepository()
        let expectedDate = Date(timeIntervalSince1970: 1_770_700_800)
        var canceledDates: [Date] = []
        let sut = LogBPMeasurementUseCase(
            measurementsRepository: repo,
            analyticsRepository: analytics,
            cancelPlannedNotification: { canceledDates.append($0) }
        )

        try await sut.execute(
            systolic: 120,
            diastolic: 80,
            pulse: 70,
            comment: nil,
            plannedScheduledDate: expectedDate
        )

        XCTAssertEqual(canceledDates, [expectedDate])
    }
}
