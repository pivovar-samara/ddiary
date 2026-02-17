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
}
