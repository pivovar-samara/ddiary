import XCTest
@testable import DDiary

@MainActor
final class GetTodayOverviewUseCaseDayRolloverTests: XCTestCase {
    // 2026-02-16 is a Monday, 2026-02-17 a Tuesday.

    func test_beforeRollover_returnsPreviousDaySlots() async throws {
        let (sut, _, userSettings) = try await makeSUT()
        userSettings.dayRolloverMinutes = 4 * 60

        let overview = await sut.compute(today: try date(day: 17, hour: 2, minute: 0))

        XCTAssertEqual(overview.bpSlots.map(\.date), [
            try date(day: 16, hour: 9, minute: 0),
            try date(day: 16, hour: 21, minute: 0)
        ])
        let dinner = try XCTUnwrap(overview.glucoseSlots.first { $0.mealSlot == .dinner && $0.measurementType == .beforeMeal })
        XCTAssertEqual(dinner.date, try date(day: 16, hour: 19, minute: 0))
        XCTAssertFalse(dinner.completed)
        XCTAssertEqual(overview.nextDayRolloverDate, try date(day: 17, hour: 4, minute: 0))
    }

    func test_beforeRollover_measurementAfterMidnight_closesPreviousDaySlot() async throws {
        let (sut, measurements, userSettings) = try await makeSUT()
        userSettings.dayRolloverMinutes = 4 * 60
        try await measurements.insertBP(
            BPMeasurement(timestamp: try date(day: 17, hour: 0, minute: 30), systolic: 120, diastolic: 80, pulse: 70, isLinkedToSchedule: true)
        )

        let overview = await sut.compute(today: try date(day: 17, hour: 1, minute: 0))

        let evening = try XCTUnwrap(overview.bpSlots.first { $0.date == (try? date(day: 16, hour: 21, minute: 0)) })
        XCTAssertTrue(evening.completed)
    }

    func test_afterRollover_returnsNewDaySlots() async throws {
        let (sut, measurements, userSettings) = try await makeSUT()
        userSettings.dayRolloverMinutes = 4 * 60
        // Logged before the rollover, so it belongs to Monday and must not complete Tuesday's slots.
        try await measurements.insertBP(
            BPMeasurement(timestamp: try date(day: 17, hour: 3, minute: 0), systolic: 120, diastolic: 80, pulse: 70, isLinkedToSchedule: true)
        )

        let overview = await sut.compute(today: try date(day: 17, hour: 5, minute: 0))

        XCTAssertEqual(overview.bpSlots.map(\.date), [
            try date(day: 17, hour: 9, minute: 0),
            try date(day: 17, hour: 21, minute: 0)
        ])
        XCTAssertTrue(overview.bpSlots.allSatisfy { !$0.completed })
    }

    func test_slotBeforeRollover_placedOnNextCalendarDate() async throws {
        let (sut, _, userSettings) = try await makeSUT()
        userSettings.dayRolloverMinutes = 4 * 60
        userSettings.bedtimeSlotEnabled = true
        userSettings.bedtimeHour = 1
        userSettings.bedtimeMinute = 0

        let overview = await sut.compute(today: try date(day: 16, hour: 12, minute: 0))

        let bedtime = try XCTUnwrap(overview.glucoseSlots.first { $0.measurementType == .bedtime })
        XCTAssertEqual(bedtime.date, try date(day: 17, hour: 1, minute: 0))
        XCTAssertEqual(overview.glucoseSlots.last?.measurementType, .bedtime)
    }

    func test_bpActiveWeekdays_useLogicalDay() async throws {
        let (sut, _, userSettings) = try await makeSUT()
        userSettings.dayRolloverMinutes = 4 * 60
        let monday = try date(day: 16, hour: 12, minute: 0)
        userSettings.bpActiveWeekdays = [Calendar.current.component(.weekday, from: monday)]

        let overview = await sut.compute(today: try date(day: 17, hour: 2, minute: 0))

        XCTAssertEqual(overview.bpSlots.count, 2)
    }

    func test_defaultRollover_matchesCalendarDay() async throws {
        let (sut, _, _) = try await makeSUT()

        let overview = await sut.compute(today: try date(day: 17, hour: 2, minute: 0))

        XCTAssertEqual(overview.bpSlots.first?.date, try date(day: 17, hour: 9, minute: 0))
        XCTAssertEqual(overview.nextDayRolloverDate, try date(day: 18, hour: 0, minute: 0))
    }

    func test_nearestGlucoseSlot_beforeRollover_usesPreviousLogicalDay() async throws {
        let (sut, _, userSettings) = try await makeSUT()
        userSettings.dayRolloverMinutes = 4 * 60
        userSettings.bedtimeSlotEnabled = true
        userSettings.bedtimeHour = 1
        userSettings.bedtimeMinute = 0

        let nearest = try await sut.nearestGlucoseSlot(to: try date(day: 17, hour: 1, minute: 30))

        XCTAssertEqual(nearest?.measurementType, .bedtime)
        XCTAssertEqual(nearest?.date, try date(day: 17, hour: 1, minute: 0))
    }

    // MARK: - Helpers

    private func makeSUT() async throws -> (GetTodayOverviewUseCase, MockMeasurementsRepository, UserSettings) {
        let measurements = MockMeasurementsRepository()
        let settings = MockSettingsRepository()
        let sut = GetTodayOverviewUseCase(measurementsRepository: measurements, settingsRepository: settings)
        let userSettings = try await settings.getOrCreate()
        userSettings.enableDailyCycleMode = false
        userSettings.enableBeforeMeal = true
        userSettings.enableAfterMeal2h = true
        userSettings.bpTimes = [9 * 60, 21 * 60]
        userSettings.bpActiveWeekdays = Set(1...7)
        return (sut, measurements, userSettings)
    }

    private func date(day: Int, hour: Int, minute: Int) throws -> Date {
        let components = DateComponents(year: 2026, month: 2, day: day, hour: hour, minute: minute)
        return try XCTUnwrap(Calendar.current.date(from: components))
    }
}
