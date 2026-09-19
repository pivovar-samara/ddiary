import XCTest
@testable import DDiary

/// Covers `nearestGlucoseSlot(to:)`, which resolves the meal tag for a manually added glucose
/// measurement. Every case passes an explicit reference date — never `Date()` — so the expectations
/// do not depend on when the suite runs.
@MainActor
final class GetTodayOverviewUseCaseNearestSlotTests: XCTestCase {

    // MARK: - Non-cycle mode

    func test_nearest_afterMidnight_bindsToYesterdayBedtime() async throws {
        let settings = MockSettingsRepository()
        let sut = makeSUT(settings: settings)

        let userSettings = try await settings.getOrCreate()
        userSettings.enableDailyCycleMode = false
        userSettings.enableBeforeMeal = true
        userSettings.enableAfterMeal2h = true
        userSettings.breakfastHour = 8
        userSettings.breakfastMinute = 0
        userSettings.bedtimeSlotEnabled = true
        userSettings.bedtimeHour = 22
        userSettings.bedtimeMinute = 0

        let reference = try date(year: 2026, month: 2, day: 17, hour: 0, minute: 30)
        let resolved = try await sut.nearestGlucoseSlot(to: reference)
        let nearest = try XCTUnwrap(resolved)

        XCTAssertEqual(nearest.mealSlot, .none)
        XCTAssertEqual(nearest.measurementType, .bedtime)
        XCTAssertEqual(nearest.date, try date(year: 2026, month: 2, day: 16, hour: 22, minute: 0))
    }

    func test_nearest_afterMidnight_withoutBedtimeSlot_bindsToYesterdayAfterDinner() async throws {
        let settings = MockSettingsRepository()
        let sut = makeSUT(settings: settings)

        let userSettings = try await settings.getOrCreate()
        userSettings.enableDailyCycleMode = false
        userSettings.enableBeforeMeal = true
        userSettings.enableAfterMeal2h = true
        userSettings.breakfastHour = 8
        userSettings.breakfastMinute = 0
        userSettings.dinnerHour = 19
        userSettings.dinnerMinute = 0
        userSettings.bedtimeSlotEnabled = false

        let reference = try date(year: 2026, month: 2, day: 17, hour: 0, minute: 30)
        let resolved = try await sut.nearestGlucoseSlot(to: reference)
        let nearest = try XCTUnwrap(resolved)

        XCTAssertEqual(nearest.mealSlot, .dinner)
        XCTAssertEqual(nearest.measurementType, .afterMeal2h)
        XCTAssertEqual(nearest.date, try date(year: 2026, month: 2, day: 16, hour: 21, minute: 0))
    }

    /// Guards against the ±1 day window hijacking ordinary daytime entries.
    func test_nearest_midday_bindsToSameDaySlot() async throws {
        let settings = MockSettingsRepository()
        let sut = makeSUT(settings: settings)

        let userSettings = try await settings.getOrCreate()
        userSettings.enableDailyCycleMode = false
        userSettings.enableBeforeMeal = true
        userSettings.enableAfterMeal2h = false
        userSettings.lunchHour = 13
        userSettings.lunchMinute = 0
        userSettings.bedtimeSlotEnabled = false

        let reference = try date(year: 2026, month: 2, day: 17, hour: 12, minute: 50)
        let resolved = try await sut.nearestGlucoseSlot(to: reference)
        let nearest = try XCTUnwrap(resolved)

        XCTAssertEqual(nearest.mealSlot, .lunch)
        XCTAssertEqual(nearest.measurementType, .beforeMeal)
        XCTAssertEqual(nearest.date, try date(year: 2026, month: 2, day: 17, hour: 13, minute: 0))
    }

    /// Proves the "tomorrow" branch is live — a yesterday-and-today-only fix would pass every other case.
    func test_nearest_lateEvening_bindsToTomorrowSlot() async throws {
        let settings = MockSettingsRepository()
        let sut = makeSUT(settings: settings)

        let userSettings = try await settings.getOrCreate()
        userSettings.enableDailyCycleMode = false
        userSettings.enableBeforeMeal = true
        userSettings.enableAfterMeal2h = false
        userSettings.breakfastHour = 1
        userSettings.breakfastMinute = 0
        userSettings.lunchHour = 13
        userSettings.lunchMinute = 0
        userSettings.dinnerHour = 19
        userSettings.dinnerMinute = 0
        userSettings.bedtimeSlotEnabled = false

        let reference = try date(year: 2026, month: 2, day: 16, hour: 23, minute: 50)
        let resolved = try await sut.nearestGlucoseSlot(to: reference)
        let nearest = try XCTUnwrap(resolved)

        XCTAssertEqual(nearest.mealSlot, .breakfast)
        XCTAssertEqual(nearest.measurementType, .beforeMeal)
        XCTAssertEqual(nearest.date, try date(year: 2026, month: 2, day: 17, hour: 1, minute: 0))
    }

    func test_nearest_whenNoSlotsConfigured_returnsNil() async throws {
        let settings = MockSettingsRepository()
        let sut = makeSUT(settings: settings)

        let userSettings = try await settings.getOrCreate()
        userSettings.enableDailyCycleMode = false
        userSettings.enableBeforeMeal = false
        userSettings.enableAfterMeal2h = false
        userSettings.bedtimeSlotEnabled = false

        let reference = try date(year: 2026, month: 2, day: 17, hour: 0, minute: 30)
        let nearest = try await sut.nearestGlucoseSlot(to: reference)

        XCTAssertNil(nearest)
    }

    func test_nearest_equidistant_prefersSlotAtOrAfterReference() async throws {
        let settings = MockSettingsRepository()
        let sut = makeSUT(settings: settings)

        let userSettings = try await settings.getOrCreate()
        userSettings.enableDailyCycleMode = false
        userSettings.enableBeforeMeal = true
        userSettings.enableAfterMeal2h = false
        userSettings.breakfastHour = 8
        userSettings.breakfastMinute = 0
        userSettings.lunchHour = 13
        userSettings.lunchMinute = 0
        userSettings.dinnerHour = 19
        userSettings.dinnerMinute = 0
        userSettings.bedtimeSlotEnabled = true
        userSettings.bedtimeHour = 22
        userSettings.bedtimeMinute = 0

        // Exactly 5h after yesterday's bedtime and 5h before today's breakfast.
        let reference = try date(year: 2026, month: 2, day: 17, hour: 3, minute: 0)
        let resolved = try await sut.nearestGlucoseSlot(to: reference)
        let nearest = try XCTUnwrap(resolved)

        XCTAssertEqual(nearest.mealSlot, .breakfast)
        XCTAssertEqual(nearest.measurementType, .beforeMeal)
        XCTAssertEqual(nearest.date, try date(year: 2026, month: 2, day: 17, hour: 8, minute: 0))
    }

    /// `MockSettingsRepository.getOrCreate()` hands back the same instance every time, so an in-place
    /// anchor mutation would be visible here even without a `save`.
    func test_nearest_doesNotPersistCycleAnchor() async throws {
        let settings = MockSettingsRepository()
        let sut = makeSUT(settings: settings)

        let userSettings = try await settings.getOrCreate()
        userSettings.enableDailyCycleMode = true
        userSettings.dailyCycleAnchorDate = nil
        userSettings.bedtimeHour = 22
        userSettings.bedtimeMinute = 0

        let reference = try date(year: 2026, month: 2, day: 17, hour: 0, minute: 30)
        _ = try await sut.nearestGlucoseSlot(to: reference)

        XCTAssertNil(userSettings.dailyCycleAnchorDate)
    }

    // MARK: - Cycle mode

    func test_cycleMode_yesterdayBedtimeDay_afterMidnight_bindsToYesterdayBedtime() async throws {
        let settings = MockSettingsRepository()
        let sut = makeSUT(settings: settings)

        let userSettings = try await settings.getOrCreate()
        userSettings.enableDailyCycleMode = true
        userSettings.breakfastHour = 8
        userSettings.breakfastMinute = 0
        userSettings.bedtimeHour = 22
        userSettings.bedtimeMinute = 0
        // Anchor on 13.02 => 16.02 is step 3 (bedtimeDay) and 17.02 is step 0 (breakfastDay).
        userSettings.dailyCycleAnchorDate = try date(year: 2026, month: 2, day: 13, hour: 0, minute: 0)

        let reference = try date(year: 2026, month: 2, day: 17, hour: 0, minute: 30)
        let resolved = try await sut.nearestGlucoseSlot(to: reference)
        let nearest = try XCTUnwrap(resolved)

        XCTAssertEqual(nearest.mealSlot, .none)
        XCTAssertEqual(nearest.measurementType, .bedtime)
        XCTAssertEqual(nearest.date, try date(year: 2026, month: 2, day: 16, hour: 22, minute: 0))
    }

    /// A per-day override must reach the previous-day branch too. Overrides for past days survive
    /// `dropFutureAndTodayOverrides` (it prunes today and later) and `pruneOverrides` (30 days).
    func test_cycleMode_respectsYesterdayOverride() async throws {
        let settings = MockSettingsRepository()
        let sut = makeSUT(settings: settings)

        let userSettings = try await settings.getOrCreate()
        userSettings.enableDailyCycleMode = true
        userSettings.breakfastHour = 8
        userSettings.breakfastMinute = 0
        userSettings.bedtimeHour = 22
        userSettings.bedtimeMinute = 0
        // Anchor on 16.02 would make 16.02 a breakfastDay; the override forces it to a bedtimeDay.
        userSettings.dailyCycleAnchorDate = try date(year: 2026, month: 2, day: 16, hour: 0, minute: 0)
        userSettings.cycleOverrides = ["2026-02-16": GlucoseCycleStep.bedtimeDay.rawValue]

        let reference = try date(year: 2026, month: 2, day: 17, hour: 0, minute: 30)
        let resolved = try await sut.nearestGlucoseSlot(to: reference)
        let nearest = try XCTUnwrap(resolved)

        XCTAssertEqual(nearest.mealSlot, .none)
        XCTAssertEqual(nearest.measurementType, .bedtime)
        XCTAssertEqual(nearest.date, try date(year: 2026, month: 2, day: 16, hour: 22, minute: 0))
    }

    func test_cycleMode_lateEvening_bindsToTomorrowSlot() async throws {
        let settings = MockSettingsRepository()
        let sut = makeSUT(settings: settings)

        let userSettings = try await settings.getOrCreate()
        userSettings.enableDailyCycleMode = true
        userSettings.breakfastHour = 1
        userSettings.breakfastMinute = 0
        userSettings.bedtimeHour = 12
        userSettings.bedtimeMinute = 0
        // Anchor on 13.02 => 16.02 is a bedtimeDay (12:00) and 17.02 a breakfastDay (01:00).
        userSettings.dailyCycleAnchorDate = try date(year: 2026, month: 2, day: 13, hour: 0, minute: 0)

        let reference = try date(year: 2026, month: 2, day: 16, hour: 23, minute: 50)
        let resolved = try await sut.nearestGlucoseSlot(to: reference)
        let nearest = try XCTUnwrap(resolved)

        XCTAssertEqual(nearest.mealSlot, .breakfast)
        XCTAssertEqual(nearest.measurementType, .beforeMeal)
        XCTAssertEqual(nearest.date, try date(year: 2026, month: 2, day: 17, hour: 1, minute: 0))
    }

    // MARK: - Failure

    /// A settings-read failure must stay distinguishable from "nothing is planned": the caller uses
    /// `nil` as a licence to fall back to a bedtime tag, and that tag cannot be edited afterwards.
    func test_nearest_whenSettingsCannotBeRead_throwsInsteadOfReturningNil() async throws {
        let sut = GetTodayOverviewUseCase(
            measurementsRepository: MockMeasurementsRepository(),
            settingsRepository: ThrowingSettingsRepository()
        )

        let reference = try date(year: 2026, month: 2, day: 17, hour: 0, minute: 30)

        do {
            _ = try await sut.nearestGlucoseSlot(to: reference)
            XCTFail("Expected nearestGlucoseSlot to propagate the settings failure")
        } catch {
            XCTAssertTrue(error is TestError)
        }
    }

    // MARK: - Helpers

    private func makeSUT(settings: MockSettingsRepository) -> GetTodayOverviewUseCase {
        GetTodayOverviewUseCase(
            measurementsRepository: MockMeasurementsRepository(),
            settingsRepository: settings
        )
    }

    private func date(year: Int, month: Int, day: Int, hour: Int, minute: Int) throws -> Date {
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        return try XCTUnwrap(Calendar.current.date(from: components))
    }
}

@MainActor
private final class ThrowingSettingsRepository: SettingsRepository {
    func getOrCreate() async throws -> UserSettings { throw TestError.forced }
    func save(_ settings: UserSettings) async throws { throw TestError.forced }
    func update(_ settings: UserSettings) async throws { throw TestError.forced }
}
