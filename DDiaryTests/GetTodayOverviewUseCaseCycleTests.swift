import XCTest
@testable import DDiary

@MainActor
final class GetTodayOverviewUseCaseCycleTests: XCTestCase {
    func test_cycleMode_breakfastDay_returnsBreakfastAndAfterBreakfastOnly() async throws {
        let measurements = MockMeasurementsRepository()
        let settings = MockSettingsRepository()
        let sut = GetTodayOverviewUseCase(measurementsRepository: measurements, settingsRepository: settings)

        let userSettings = try await settings.getOrCreate()
        userSettings.enableDailyCycleMode = true
        userSettings.currentCycleIndex = 0

        let fixedToday = Date(timeIntervalSince1970: 1_735_689_600) // 2025-01-01 00:00:00 UTC
        let overview = await sut.compute(today: fixedToday)

        XCTAssertTrue(overview.isDailyCycleModeEnabled)
        XCTAssertEqual(overview.glucoseSlots.count, 2)
        XCTAssertEqual(Set(overview.glucoseSlots.map(\.mealSlot)), [.breakfast])
        XCTAssertEqual(Set(overview.glucoseSlots.map(\.measurementType)), [.beforeMeal, .afterMeal2h])
    }

    func test_cycleMode_lunchDay_returnsLunchAndAfterLunchOnly() async throws {
        let measurements = MockMeasurementsRepository()
        let settings = MockSettingsRepository()
        let sut = GetTodayOverviewUseCase(measurementsRepository: measurements, settingsRepository: settings)

        let userSettings = try await settings.getOrCreate()
        userSettings.enableDailyCycleMode = true
        userSettings.currentCycleIndex = 1

        let fixedToday = Date(timeIntervalSince1970: 1_735_689_600) // 2025-01-01 00:00:00 UTC
        let overview = await sut.compute(today: fixedToday)

        XCTAssertEqual(overview.glucoseSlots.count, 2)
        XCTAssertEqual(Set(overview.glucoseSlots.map(\.mealSlot)), [.lunch])
        XCTAssertEqual(Set(overview.glucoseSlots.map(\.measurementType)), [.beforeMeal, .afterMeal2h])
    }

    func test_cycleMode_dinnerDay_returnsDinnerAndAfterDinnerOnly() async throws {
        let measurements = MockMeasurementsRepository()
        let settings = MockSettingsRepository()
        let sut = GetTodayOverviewUseCase(measurementsRepository: measurements, settingsRepository: settings)

        let userSettings = try await settings.getOrCreate()
        userSettings.enableDailyCycleMode = true
        userSettings.currentCycleIndex = 2

        let fixedToday = Date(timeIntervalSince1970: 1_735_689_600) // 2025-01-01 00:00:00 UTC
        let overview = await sut.compute(today: fixedToday)

        XCTAssertEqual(overview.glucoseSlots.count, 2)
        XCTAssertEqual(Set(overview.glucoseSlots.map(\.mealSlot)), [.dinner])
        XCTAssertEqual(Set(overview.glucoseSlots.map(\.measurementType)), [.beforeMeal, .afterMeal2h])
    }

    func test_cycleMode_bedtimeDay_returnsBedtimeOnly() async throws {
        let measurements = MockMeasurementsRepository()
        let settings = MockSettingsRepository()
        let sut = GetTodayOverviewUseCase(measurementsRepository: measurements, settingsRepository: settings)

        let userSettings = try await settings.getOrCreate()
        userSettings.enableDailyCycleMode = true
        userSettings.currentCycleIndex = 3

        let fixedToday = Date(timeIntervalSince1970: 1_735_689_600) // 2025-01-01 00:00:00 UTC
        let overview = await sut.compute(today: fixedToday)

        XCTAssertEqual(overview.glucoseSlots.count, 1)
        XCTAssertEqual(overview.glucoseSlots.first?.mealSlot, MealSlot.none)
        XCTAssertEqual(overview.glucoseSlots.first?.measurementType, .bedtime)
    }
}
