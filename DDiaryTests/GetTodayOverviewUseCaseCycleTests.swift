import XCTest
@testable import DDiary

@MainActor
final class GetTodayOverviewUseCaseCycleTests: XCTestCase {
    func test_nonCycle_afterMealSlotShiftsFromLoggedBeforeMealTimestamp() async throws {
        let measurements = MockMeasurementsRepository()
        let settings = MockSettingsRepository()
        let sut = GetTodayOverviewUseCase(measurementsRepository: measurements, settingsRepository: settings)

        let userSettings = try await settings.getOrCreate()
        userSettings.enableDailyCycleMode = false
        userSettings.enableBeforeMeal = true
        userSettings.enableAfterMeal2h = true
        userSettings.lunchHour = 13
        userSettings.lunchMinute = 0

        let fixedToday = try date(year: 2025, month: 1, day: 1, hour: 9, minute: 0)
        let beforeLunchTimestamp = try date(year: 2025, month: 1, day: 1, hour: 13, minute: 20)
        try await measurements.insertGlucose(
            GlucoseMeasurement(
                id: UUID(),
                timestamp: beforeLunchTimestamp,
                value: 5.4,
                unit: .mmolL,
                measurementType: .beforeMeal,
                mealSlot: .lunch,
                comment: nil
            )
        )

        let overview = await sut.compute(today: fixedToday)
        let afterLunch = try XCTUnwrap(
            overview.glucoseSlots.first(where: { $0.mealSlot == .lunch && $0.measurementType == .afterMeal2h })
        )
        let beforeLunch = try XCTUnwrap(
            overview.glucoseSlots.first(where: { $0.mealSlot == .lunch && $0.measurementType == .beforeMeal })
        )
        let expectedAfterLunch = try XCTUnwrap(Calendar.current.date(byAdding: .hour, value: 2, to: beforeLunchTimestamp))

        XCTAssertEqual(afterLunch.date, expectedAfterLunch)
        XCTAssertEqual(beforeLunch.date, try date(year: 2025, month: 1, day: 1, hour: 13, minute: 0))
    }

    func test_nonCycle_afterMealSlotStaysPlannedWhenNoBeforeMealLogged() async throws {
        let measurements = MockMeasurementsRepository()
        let settings = MockSettingsRepository()
        let sut = GetTodayOverviewUseCase(measurementsRepository: measurements, settingsRepository: settings)

        let userSettings = try await settings.getOrCreate()
        userSettings.enableDailyCycleMode = false
        userSettings.enableBeforeMeal = true
        userSettings.enableAfterMeal2h = true
        userSettings.lunchHour = 13
        userSettings.lunchMinute = 0

        let fixedToday = try date(year: 2025, month: 1, day: 1, hour: 9, minute: 0)
        let overview = await sut.compute(today: fixedToday)
        let afterLunch = try XCTUnwrap(
            overview.glucoseSlots.first(where: { $0.mealSlot == .lunch && $0.measurementType == .afterMeal2h })
        )

        XCTAssertEqual(afterLunch.date, try date(year: 2025, month: 1, day: 1, hour: 15, minute: 0))
    }

    func test_nonCycle_whenTodayWeekdayNotActive_returnsNoBPSlots() async throws {
        let measurements = MockMeasurementsRepository()
        let settings = MockSettingsRepository()
        let sut = GetTodayOverviewUseCase(measurementsRepository: measurements, settingsRepository: settings)

        let userSettings = try await settings.getOrCreate()
        userSettings.bpTimes = [9 * 60, 21 * 60]

        let fixedToday = try date(year: 2026, month: 2, day: 16, hour: 9, minute: 0)
        let weekday = Calendar.current.component(.weekday, from: fixedToday)
        userSettings.bpActiveWeekdays = Set((1...7).filter { $0 != weekday })

        let overview = await sut.compute(today: fixedToday)

        XCTAssertTrue(overview.bpSlots.isEmpty)
    }

    func test_nonCycle_whenTodayWeekdayActive_returnsBPSlots() async throws {
        let measurements = MockMeasurementsRepository()
        let settings = MockSettingsRepository()
        let sut = GetTodayOverviewUseCase(measurementsRepository: measurements, settingsRepository: settings)

        let userSettings = try await settings.getOrCreate()
        userSettings.bpTimes = [9 * 60, 21 * 60]

        let fixedToday = try date(year: 2026, month: 2, day: 16, hour: 9, minute: 0)
        let weekday = Calendar.current.component(.weekday, from: fixedToday)
        userSettings.bpActiveWeekdays = [weekday]

        let overview = await sut.compute(today: fixedToday)

        XCTAssertEqual(overview.bpSlots.count, 2)
    }

    func test_nonCycle_manualBPMeasurement_doesNotCompleteScheduledSlot() async throws {
        let measurements = MockMeasurementsRepository()
        let settings = MockSettingsRepository()
        let sut = GetTodayOverviewUseCase(measurementsRepository: measurements, settingsRepository: settings)

        let fixedToday = try date(year: 2026, month: 2, day: 16, hour: 9, minute: 0)
        let userSettings = try await settings.getOrCreate()
        userSettings.bpTimes = [9 * 60]
        userSettings.bpActiveWeekdays = [Calendar.current.component(.weekday, from: fixedToday)]

        try await measurements.insertBP(
            BPMeasurement(
                id: UUID(),
                timestamp: try date(year: 2026, month: 2, day: 16, hour: 9, minute: 5),
                systolic: 120,
                diastolic: 80,
                pulse: 70,
                comment: nil,
                isLinkedToSchedule: false
            )
        )

        let overview = await sut.compute(today: fixedToday)
        XCTAssertEqual(overview.bpSlots.count, 1)
        XCTAssertFalse(overview.bpSlots[0].completed)
    }

    func test_nonCycle_linkedBPMeasurement_completesScheduledSlot() async throws {
        let measurements = MockMeasurementsRepository()
        let settings = MockSettingsRepository()
        let sut = GetTodayOverviewUseCase(measurementsRepository: measurements, settingsRepository: settings)

        let fixedToday = try date(year: 2026, month: 2, day: 16, hour: 9, minute: 0)
        let userSettings = try await settings.getOrCreate()
        userSettings.bpTimes = [9 * 60]
        userSettings.bpActiveWeekdays = [Calendar.current.component(.weekday, from: fixedToday)]

        try await measurements.insertBP(
            BPMeasurement(
                id: UUID(),
                timestamp: try date(year: 2026, month: 2, day: 16, hour: 9, minute: 5),
                systolic: 120,
                diastolic: 80,
                pulse: 70,
                comment: nil,
                isLinkedToSchedule: true
            )
        )

        let overview = await sut.compute(today: fixedToday)
        XCTAssertEqual(overview.bpSlots.count, 1)
        XCTAssertTrue(overview.bpSlots[0].completed)
    }

    func test_nonCycle_manualGlucoseMeasurement_doesNotCompleteScheduledSlot() async throws {
        let measurements = MockMeasurementsRepository()
        let settings = MockSettingsRepository()
        let sut = GetTodayOverviewUseCase(measurementsRepository: measurements, settingsRepository: settings)

        let fixedToday = try date(year: 2026, month: 2, day: 16, hour: 9, minute: 0)
        let userSettings = try await settings.getOrCreate()
        userSettings.enableDailyCycleMode = false
        userSettings.enableBeforeMeal = true
        userSettings.enableAfterMeal2h = false
        userSettings.breakfastHour = 9
        userSettings.breakfastMinute = 0
        userSettings.lunchHour = 13
        userSettings.lunchMinute = 0
        userSettings.dinnerHour = 19
        userSettings.dinnerMinute = 0

        try await measurements.insertGlucose(
            GlucoseMeasurement(
                id: UUID(),
                timestamp: try date(year: 2026, month: 2, day: 16, hour: 9, minute: 10),
                value: 5.5,
                unit: .mmolL,
                measurementType: .beforeMeal,
                mealSlot: .breakfast,
                comment: nil,
                isLinkedToSchedule: false
            )
        )

        let overview = await sut.compute(today: fixedToday)
        let breakfastBefore = try XCTUnwrap(
            overview.glucoseSlots.first(where: { $0.mealSlot == .breakfast && $0.measurementType == .beforeMeal })
        )
        XCTAssertFalse(breakfastBefore.completed)
    }

    func test_nonCycle_linkedGlucoseMeasurement_completesScheduledSlot() async throws {
        let measurements = MockMeasurementsRepository()
        let settings = MockSettingsRepository()
        let sut = GetTodayOverviewUseCase(measurementsRepository: measurements, settingsRepository: settings)

        let fixedToday = try date(year: 2026, month: 2, day: 16, hour: 9, minute: 0)
        let userSettings = try await settings.getOrCreate()
        userSettings.enableDailyCycleMode = false
        userSettings.enableBeforeMeal = true
        userSettings.enableAfterMeal2h = false
        userSettings.breakfastHour = 9
        userSettings.breakfastMinute = 0
        userSettings.lunchHour = 13
        userSettings.lunchMinute = 0
        userSettings.dinnerHour = 19
        userSettings.dinnerMinute = 0

        try await measurements.insertGlucose(
            GlucoseMeasurement(
                id: UUID(),
                timestamp: try date(year: 2026, month: 2, day: 16, hour: 9, minute: 10),
                value: 5.5,
                unit: .mmolL,
                measurementType: .beforeMeal,
                mealSlot: .breakfast,
                comment: nil,
                isLinkedToSchedule: true
            )
        )

        let overview = await sut.compute(today: fixedToday)
        let breakfastBefore = try XCTUnwrap(
            overview.glucoseSlots.first(where: { $0.mealSlot == .breakfast && $0.measurementType == .beforeMeal })
        )
        XCTAssertTrue(breakfastBefore.completed)
    }

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

    func test_cycleMode_afterMealSlotShiftsFromLoggedBeforeMealTimestamp() async throws {
        let measurements = MockMeasurementsRepository()
        let settings = MockSettingsRepository()
        let sut = GetTodayOverviewUseCase(measurementsRepository: measurements, settingsRepository: settings)

        let userSettings = try await settings.getOrCreate()
        userSettings.enableDailyCycleMode = true
        userSettings.currentCycleIndex = 1
        userSettings.lunchHour = 13
        userSettings.lunchMinute = 0

        let fixedToday = try date(year: 2025, month: 1, day: 1, hour: 9, minute: 0)
        let beforeLunchTimestamp = try date(year: 2025, month: 1, day: 1, hour: 13, minute: 20)
        try await measurements.insertGlucose(
            GlucoseMeasurement(
                id: UUID(),
                timestamp: beforeLunchTimestamp,
                value: 5.1,
                unit: .mmolL,
                measurementType: .beforeMeal,
                mealSlot: .lunch,
                comment: nil
            )
        )

        let overview = await sut.compute(today: fixedToday)
        let afterLunch = try XCTUnwrap(
            overview.glucoseSlots.first(where: { $0.mealSlot == .lunch && $0.measurementType == .afterMeal2h })
        )
        let expectedAfterLunch = try XCTUnwrap(Calendar.current.date(byAdding: .hour, value: 2, to: beforeLunchTimestamp))

        XCTAssertEqual(afterLunch.date, expectedAfterLunch)
    }

    private func date(year: Int, month: Int, day: Int, hour: Int, minute: Int) throws -> Date {
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        return try XCTUnwrap(Calendar.current.date(from: components))
    }
}
