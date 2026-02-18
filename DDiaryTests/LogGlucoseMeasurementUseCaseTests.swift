//
//  LogGlucoseMeasurementUseCaseTests.swift
//  DDiary
//
//  Created by Ilia Khokhlov on 10.12.25.
//

import XCTest
@testable import DDiary

@MainActor
final class LogGlucoseMeasurementUseCaseTests: XCTestCase {
    func test_happyPath_insertsWithUserUnit_andLogsAnalytics() async throws {
        let measurements = MockMeasurementsRepository()
        let settings = MockSettingsRepository()
        let analytics = MockAnalyticsRepository()
        var syncScheduleCount = 0
        let sut = LogGlucoseMeasurementUseCase(
            measurementsRepository: measurements,
            settingsRepository: settings,
            analyticsRepository: analytics,
            scheduleGoogleSyncIfConnected: { syncScheduleCount += 1 }
        )

        try await sut.execute(value: 5.5, measurementType: .beforeMeal, mealSlot: .breakfast, comment: "fasting")

        let all = try await measurements.glucoseMeasurements(from: Date.distantPast, to: Date.distantFuture)
        XCTAssertEqual(all.count, 1)
        let settingsUnit = try await settings.getOrCreate().glucoseUnit
        XCTAssertEqual(all.first?.unit, settingsUnit)
        XCTAssertEqual(all.first?.googleSyncStatus, .pending)
        XCTAssertEqual(analytics.measurementLogged, [.glucose])
        XCTAssertEqual(syncScheduleCount, 1)
    }

    func test_errorPath_repositoryThrows() async throws {
        @MainActor
        final class ThrowingSettingsRepository: SettingsRepository {
            func getOrCreate() async throws -> UserSettings { throw TestError.forced }
            func save(_ settings: UserSettings) async throws {}
            func update(_ settings: UserSettings) async throws {}
        }
        let measurements = MockMeasurementsRepository()
        let settings = ThrowingSettingsRepository()
        let analytics = MockAnalyticsRepository()
        var syncScheduleCount = 0
        let sut = LogGlucoseMeasurementUseCase(
            measurementsRepository: measurements,
            settingsRepository: settings,
            analyticsRepository: analytics,
            scheduleGoogleSyncIfConnected: { syncScheduleCount += 1 }
        )

        await XCTAssertThrowsErrorAsync(try await sut.execute(value: 4.2, measurementType: .beforeMeal, mealSlot: .breakfast, comment: nil))
        let all = try await measurements.glucoseMeasurements(from: Date.distantPast, to: Date.distantFuture)
        XCTAssertTrue(all.isEmpty)
        XCTAssertTrue(analytics.measurementLogged.isEmpty)
        XCTAssertEqual(syncScheduleCount, 0)
    }

    func test_cycleMode_loggingBeforeMeal_doesNotAdvanceCurrentCycleIndex() async throws {
        let measurements = MockMeasurementsRepository()
        let settings = MockSettingsRepository()
        let analytics = MockAnalyticsRepository()
        let sut = LogGlucoseMeasurementUseCase(measurementsRepository: measurements, settingsRepository: settings, analyticsRepository: analytics)

        let userSettings = try await settings.getOrCreate()
        userSettings.enableDailyCycleMode = true
        userSettings.enableBeforeMeal = true
        userSettings.bedtimeSlotEnabled = false
        userSettings.currentCycleIndex = 0 // breakfast

        try await sut.execute(value: 5.3, measurementType: .beforeMeal, mealSlot: .breakfast, comment: nil)

        XCTAssertEqual(userSettings.currentCycleIndex, 0)
    }

    func test_cycleMode_loggingNonTargetBeforeMeal_keepsCurrentCycleIndex() async throws {
        let measurements = MockMeasurementsRepository()
        let settings = MockSettingsRepository()
        let analytics = MockAnalyticsRepository()
        let sut = LogGlucoseMeasurementUseCase(measurementsRepository: measurements, settingsRepository: settings, analyticsRepository: analytics)

        let userSettings = try await settings.getOrCreate()
        userSettings.enableDailyCycleMode = true
        userSettings.enableBeforeMeal = true
        userSettings.bedtimeSlotEnabled = false
        userSettings.currentCycleIndex = 1 // lunch

        try await sut.execute(value: 5.3, measurementType: .beforeMeal, mealSlot: .breakfast, comment: nil)

        XCTAssertEqual(userSettings.currentCycleIndex, 1)
    }

    func test_withPlannedScheduledDate_cancelsPlannedNotification() async throws {
        let measurements = MockMeasurementsRepository()
        let settings = MockSettingsRepository()
        let analytics = MockAnalyticsRepository()
        let expectedDate = Date(timeIntervalSince1970: 1_770_700_800)
        var canceled: [(GlucoseMeasurementType, Date)] = []
        let sut = LogGlucoseMeasurementUseCase(
            measurementsRepository: measurements,
            settingsRepository: settings,
            analyticsRepository: analytics,
            cancelPlannedNotification: { canceled.append(($0, $1)) }
        )

        try await sut.execute(
            value: 5.5,
            measurementType: .beforeMeal,
            mealSlot: .breakfast,
            comment: nil,
            plannedScheduledDate: expectedDate
        )

        XCTAssertEqual(canceled.count, 1)
        XCTAssertEqual(canceled.first?.0, .beforeMeal)
        XCTAssertEqual(canceled.first?.1, expectedDate)
    }

    func test_beforeMealWithPlannedScheduledDate_reschedulesShiftedAfterMealNotification() async throws {
        let measurements = MockMeasurementsRepository()
        let settings = MockSettingsRepository()
        let analytics = MockAnalyticsRepository()
        let plannedBeforeDate = Date(timeIntervalSince1970: 1_770_700_800)
        var rescheduled: [(MealSlot, Date, Date)] = []
        let sut = LogGlucoseMeasurementUseCase(
            measurementsRepository: measurements,
            settingsRepository: settings,
            analyticsRepository: analytics,
            rescheduleShiftedAfterMealNotification: { rescheduled.append(($0, $1, $2)) }
        )

        try await sut.execute(
            value: 5.2,
            measurementType: .beforeMeal,
            mealSlot: .lunch,
            comment: nil,
            plannedScheduledDate: plannedBeforeDate
        )

        let loggedMeasurements = try await measurements.glucoseMeasurements(from: .distantPast, to: .distantFuture)
        let logged = try XCTUnwrap(loggedMeasurements.first)
        let calendar = Calendar.current
        let expectedOriginalAfter = try XCTUnwrap(calendar.date(byAdding: .hour, value: 2, to: plannedBeforeDate))
        let expectedShiftedAfter = try XCTUnwrap(calendar.date(byAdding: .hour, value: 2, to: logged.timestamp))

        XCTAssertEqual(rescheduled.count, 1)
        XCTAssertEqual(rescheduled.first?.0, .lunch)
        XCTAssertEqual(rescheduled.first?.1, expectedOriginalAfter)
        XCTAssertEqual(rescheduled.first?.2, expectedShiftedAfter)
    }

    func test_nonBeforeMealWithPlannedScheduledDate_doesNotRescheduleShiftedAfterMealNotification() async throws {
        let measurements = MockMeasurementsRepository()
        let settings = MockSettingsRepository()
        let analytics = MockAnalyticsRepository()
        let plannedDate = Date(timeIntervalSince1970: 1_770_700_800)
        var rescheduleCallCount = 0
        let sut = LogGlucoseMeasurementUseCase(
            measurementsRepository: measurements,
            settingsRepository: settings,
            analyticsRepository: analytics,
            rescheduleShiftedAfterMealNotification: { _, _, _ in rescheduleCallCount += 1 }
        )

        try await sut.execute(
            value: 5.2,
            measurementType: .afterMeal2h,
            mealSlot: .lunch,
            comment: nil,
            plannedScheduledDate: plannedDate
        )

        XCTAssertEqual(rescheduleCallCount, 0)
    }
}
