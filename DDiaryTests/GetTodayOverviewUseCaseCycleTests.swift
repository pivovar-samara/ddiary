import XCTest
@testable import DDiary

@MainActor
final class GetTodayOverviewUseCaseCycleTests: XCTestCase {
    func test_cycleMode_returnsOnlyCurrentBeforeMealTarget() async throws {
        let measurements = MockMeasurementsRepository()
        let settings = MockSettingsRepository()
        let sut = GetTodayOverviewUseCase(measurementsRepository: measurements, settingsRepository: settings)

        let userSettings = try await settings.getOrCreate()
        userSettings.enableBeforeMeal = true
        userSettings.enableDailyCycleMode = true
        userSettings.bedtimeSlotEnabled = false
        userSettings.currentCycleIndex = 1 // lunch

        let fixedToday = Date(timeIntervalSince1970: 1_735_689_600) // 2025-01-01 00:00:00 UTC
        let overview = await sut.compute(today: fixedToday)
        let beforeMealSlots = overview.glucoseSlots.filter { $0.measurementType == .beforeMeal }

        XCTAssertEqual(beforeMealSlots.count, 1)
        XCTAssertEqual(beforeMealSlots.first?.mealSlot, .lunch)
    }

    func test_cycleMode_bedtimeTarget_hidesBeforeMealSlots() async throws {
        let measurements = MockMeasurementsRepository()
        let settings = MockSettingsRepository()
        let sut = GetTodayOverviewUseCase(measurementsRepository: measurements, settingsRepository: settings)

        let userSettings = try await settings.getOrCreate()
        userSettings.enableBeforeMeal = true
        userSettings.enableDailyCycleMode = true
        userSettings.bedtimeSlotEnabled = true
        userSettings.currentCycleIndex = 3 // bedtime step (`MealSlot.none`)

        let fixedToday = Date(timeIntervalSince1970: 1_735_689_600) // 2025-01-01 00:00:00 UTC
        let overview = await sut.compute(today: fixedToday)
        let beforeMealSlots = overview.glucoseSlots.filter { $0.measurementType == .beforeMeal }

        XCTAssertTrue(beforeMealSlots.isEmpty)
    }
}
