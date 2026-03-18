import XCTest
@testable import DDiary

@MainActor
final class RescheduleGlucoseCycleUseCaseTests: XCTestCase {

    // Tests use Calendar.current so that anchor setup and SUT computation both use the same
    // timezone. All `today` values are at hour 9–21 local time (well clear of midnight) so
    // startOfDay is unambiguous in any UTC±12 timezone.

    // MARK: - advanceIfEnabled (no-op)

    func test_advanceIfEnabled_isNoOp_doesNotMutateSettings() async throws {
        let settings = UserSettings.default()
        settings.enableDailyCycleMode = true
        let calendar = Calendar.current
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 16)))
        settings.dailyCycleAnchorDate = calendar.startOfDay(for: today)
        let originalAnchor = settings.dailyCycleAnchorDate

        let settingsRepository = SpyCycleSettingsRepository(settings: settings)
        let analyticsRepository = MockAnalyticsRepository()
        let sut = RescheduleGlucoseCycleUseCase(
            settingsRepository: settingsRepository,
            analyticsRepository: analyticsRepository
        )

        await sut.advanceIfEnabled(today: today)

        XCTAssertEqual(settings.dailyCycleAnchorDate, originalAnchor)
        XCTAssertEqual(settings.cycleOverrides, [:])
        XCTAssertEqual(settingsRepository.saveCount, 0)
        XCTAssertTrue(analyticsRepository.scheduleUpdated.isEmpty)
    }

    // MARK: - setTarget

    func test_setTarget_ignoresWhenCycleModeDisabled() async {
        let settings = UserSettings.default()
        settings.enableDailyCycleMode = false
        settings.dailyCycleAnchorDate = nil

        let settingsRepository = SpyCycleSettingsRepository(settings: settings)
        let analyticsRepository = MockAnalyticsRepository()
        let sut = RescheduleGlucoseCycleUseCase(
            settingsRepository: settingsRepository,
            analyticsRepository: analyticsRepository
        )

        await sut.setTarget(.dinner)

        XCTAssertNil(settings.dailyCycleAnchorDate)
        XCTAssertEqual(settings.cycleOverrides, [:])
        XCTAssertEqual(settingsRepository.saveCount, 0)
        XCTAssertTrue(analyticsRepository.scheduleUpdated.isEmpty)
    }

    func test_setTarget_bedtimeDisabled_rejectsBedtimeSlot() async throws {
        let settings = UserSettings.default()
        settings.enableDailyCycleMode = true
        settings.bedtimeSlotEnabled = false
        let calendar = Calendar.current
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 16)))
        settings.dailyCycleAnchorDate = calendar.startOfDay(for: today)

        let settingsRepository = SpyCycleSettingsRepository(settings: settings)
        let analyticsRepository = MockAnalyticsRepository()
        let sut = RescheduleGlucoseCycleUseCase(
            settingsRepository: settingsRepository,
            analyticsRepository: analyticsRepository
        )

        await sut.setTarget(.none, today: today)

        XCTAssertEqual(settings.cycleOverrides, [:])
        XCTAssertEqual(settingsRepository.saveCount, 0)
        XCTAssertTrue(analyticsRepository.scheduleUpdated.isEmpty)
    }

    func test_setTarget_updatesAnchorForToday() async throws {
        let settings = UserSettings.default()
        settings.enableDailyCycleMode = true
        settings.bedtimeSlotEnabled = true
        let calendar = Calendar.current
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 16, hour: 10)))
        settings.dailyCycleAnchorDate = calendar.startOfDay(for: today) // breakfast day

        let settingsRepository = SpyCycleSettingsRepository(settings: settings)
        let sut = RescheduleGlucoseCycleUseCase(
            settingsRepository: settingsRepository,
            analyticsRepository: MockAnalyticsRepository()
        )

        await sut.setTarget(.dinner, today: today)

        // Anchor updated so today = dinnerDay (step 2): anchor = today - 2 days
        let expectedAnchor = calendar.date(byAdding: .day, value: -2, to: calendar.startOfDay(for: today))
        XCTAssertEqual(settings.dailyCycleAnchorDate, expectedAnchor)
        XCTAssertEqual(settingsRepository.saveCount, 1)
        let target = await sut.currentTarget(today: today)
        XCTAssertEqual(target, .dinner)
    }

    func test_setTarget_rescheduleTodayFromBedtimeToLunch_tomorrowIsDinner() async throws {
        // Regression: rescheduling today must propagate to subsequent days.
        let settings = UserSettings.default()
        settings.enableDailyCycleMode = true
        settings.bedtimeSlotEnabled = true
        let calendar = Calendar.current
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 16, hour: 21)))
        // anchor = today - 3 days → bedtime day (step 3)
        settings.dailyCycleAnchorDate = calendar.date(byAdding: .day, value: -3, to: calendar.startOfDay(for: today))

        let sut = RescheduleGlucoseCycleUseCase(
            settingsRepository: SpyCycleSettingsRepository(settings: settings),
            analyticsRepository: MockAnalyticsRepository()
        )

        await sut.setTarget(.lunch, today: today)

        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: today))
        let tomorrowTarget = await sut.currentTarget(today: tomorrow)
        XCTAssertEqual(tomorrowTarget, .dinner)
        let dayAfter = try XCTUnwrap(calendar.date(byAdding: .day, value: 2, to: today))
        let dayAfterTarget = await sut.currentTarget(today: dayAfter)
        XCTAssertEqual(dayAfterTarget, MealSlot.none) // bedtime
    }

    // MARK: - currentTarget

    func test_currentTarget_fallbackFromLegacyNegativeIndex() async {
        // currentCycleIndex = -1 is a legacy field; fallbackAnchorDate maps it to step 3 (bedtime).
        // The math is self-referential: fallback uses today to compute anchor,
        // then step uses today against that same anchor → always yields step 3 for index -1.
        let settings = UserSettings.default()
        settings.enableDailyCycleMode = true
        settings.bedtimeSlotEnabled = true
        settings.currentCycleIndex = -1
        // dailyCycleAnchorDate is nil so the fallback path is exercised

        let sut = RescheduleGlucoseCycleUseCase(
            settingsRepository: SpyCycleSettingsRepository(settings: settings),
            analyticsRepository: MockAnalyticsRepository()
        )

        let target = await sut.currentTarget()

        XCTAssertEqual(target, MealSlot.none)
    }

    // MARK: - shiftTodayForward

    func test_shiftTodayForward_updatesAnchorAndRotatesTarget() async throws {
        let settings = UserSettings.default()
        settings.enableDailyCycleMode = true
        settings.currentCycleIndex = 0
        let calendar = Calendar.current
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 16, hour: 9, minute: 0)))
        settings.dailyCycleAnchorDate = calendar.startOfDay(for: today) // breakfast day

        let settingsRepository = SpyCycleSettingsRepository(settings: settings)
        let sut = RescheduleGlucoseCycleUseCase(
            settingsRepository: settingsRepository,
            analyticsRepository: MockAnalyticsRepository()
        )

        let shifted = await sut.shiftTodayForward(today: today)

        XCTAssertTrue(shifted)
        // Anchor updated so today = lunchDay (step 1): anchor = today - 1 day.
        let expectedAnchor = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: today))
        XCTAssertEqual(settings.dailyCycleAnchorDate, expectedAnchor)
        XCTAssertEqual(settingsRepository.saveCount, 1)
        let target = await sut.currentTarget(today: today)
        XCTAssertEqual(target, .lunch)
    }

    func test_shiftTodayForward_wrapsFromBedtimeToBreakfast() async throws {
        let settings = UserSettings.default()
        settings.enableDailyCycleMode = true
        settings.bedtimeSlotEnabled = true
        let calendar = Calendar.current
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 16, hour: 9)))
        // anchor = today - 3 days → bedtime day (step 3)
        settings.dailyCycleAnchorDate = calendar.date(byAdding: .day, value: -3, to: calendar.startOfDay(for: today))

        let sut = RescheduleGlucoseCycleUseCase(
            settingsRepository: SpyCycleSettingsRepository(settings: settings),
            analyticsRepository: MockAnalyticsRepository()
        )

        let shifted = await sut.shiftTodayForward(today: today)
        XCTAssertTrue(shifted)
        let target = await sut.currentTarget(today: today)
        XCTAssertEqual(target, .breakfast) // wraps back to step 0
    }

    func test_shiftTodayForward_returnsFalseWhenCycleModeDisabled() async {
        let settings = UserSettings.default()
        settings.enableDailyCycleMode = false
        settings.currentCycleIndex = 0
        settings.dailyCycleAnchorDate = Date(timeIntervalSince1970: 1_700_000_000)

        let settingsRepository = SpyCycleSettingsRepository(settings: settings)
        let sut = RescheduleGlucoseCycleUseCase(
            settingsRepository: settingsRepository,
            analyticsRepository: MockAnalyticsRepository()
        )

        let shifted = await sut.shiftTodayForward()

        XCTAssertFalse(shifted)
        XCTAssertEqual(settings.dailyCycleAnchorDate, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(settings.cycleOverrides, [:])
        XCTAssertEqual(settingsRepository.saveCount, 0)
    }

    // MARK: - availableForwardTargetsForToday

    func test_availableForwardTargetsForToday_returnsCanonicalOrderExcludingCurrent() async throws {
        let settings = UserSettings.default()
        settings.enableDailyCycleMode = true
        settings.bedtimeSlotEnabled = true
        settings.breakfastHour = 8;  settings.breakfastMinute = 0
        settings.lunchHour = 13;     settings.lunchMinute = 0
        settings.dinnerHour = 19;    settings.dinnerMinute = 0
        settings.bedtimeHour = 22;   settings.bedtimeMinute = 0
        let calendar = Calendar.current
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 16, hour: 12, minute: 30)))
        settings.dailyCycleAnchorDate = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: today))

        let targets = await RescheduleGlucoseCycleUseCase(
            settingsRepository: SpyCycleSettingsRepository(settings: settings),
            analyticsRepository: MockAnalyticsRepository()
        ).availableForwardTargetsForToday(today: today)

        XCTAssertEqual(targets, [.breakfast, .dinner, .none])
    }

    func test_availableForwardTargetsForToday_dinnerDay_includesBedtimeBreakfastLunch() async throws {
        let settings = UserSettings.default()
        settings.enableDailyCycleMode = true
        settings.bedtimeSlotEnabled = true
        settings.breakfastHour = 8;  settings.breakfastMinute = 0
        settings.lunchHour = 13;     settings.lunchMinute = 0
        settings.dinnerHour = 19;    settings.dinnerMinute = 0
        settings.bedtimeHour = 22;   settings.bedtimeMinute = 0
        let calendar = Calendar.current
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 16, hour: 18, minute: 0)))
        settings.dailyCycleAnchorDate = calendar.date(byAdding: .day, value: -2, to: calendar.startOfDay(for: today))

        let targets = await RescheduleGlucoseCycleUseCase(
            settingsRepository: SpyCycleSettingsRepository(settings: settings),
            analyticsRepository: MockAnalyticsRepository()
        ).availableForwardTargetsForToday(today: today)

        XCTAssertEqual(targets, [.breakfast, .lunch, .none])
    }

    func test_availableForwardTargetsForToday_bedtimeDay_includesBreakfastLunchDinner() async throws {
        let settings = UserSettings.default()
        settings.enableDailyCycleMode = true
        settings.breakfastHour = 8;  settings.breakfastMinute = 0
        settings.lunchHour = 13;     settings.lunchMinute = 0
        settings.dinnerHour = 19;    settings.dinnerMinute = 0
        settings.bedtimeHour = 22;   settings.bedtimeMinute = 0
        let calendar = Calendar.current
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 16, hour: 21, minute: 0)))
        settings.dailyCycleAnchorDate = calendar.date(byAdding: .day, value: -3, to: calendar.startOfDay(for: today))

        let targets = await RescheduleGlucoseCycleUseCase(
            settingsRepository: SpyCycleSettingsRepository(settings: settings),
            analyticsRepository: MockAnalyticsRepository()
        ).availableForwardTargetsForToday(today: today)

        XCTAssertEqual(targets, [.breakfast, .lunch, .dinner])
    }

    func test_availableForwardTargets_dinnerDay_bedtimeDisabled_excludesBedtime() async throws {
        let settings = UserSettings.default()
        settings.enableDailyCycleMode = true
        settings.bedtimeSlotEnabled = false
        let calendar = Calendar.current
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 16, hour: 18, minute: 0)))
        settings.dailyCycleAnchorDate = calendar.date(byAdding: .day, value: -2, to: calendar.startOfDay(for: today))

        let targets = await RescheduleGlucoseCycleUseCase(
            settingsRepository: SpyCycleSettingsRepository(settings: settings),
            analyticsRepository: MockAnalyticsRepository()
        ).availableForwardTargetsForToday(today: today)

        XCTAssertEqual(targets, [.breakfast, .lunch])
        XCTAssertFalse(targets.contains(.none))
    }

    // MARK: - setTodayTarget

    func test_setTodayTarget_updatesAnchor() async throws {
        let settings = UserSettings.default()
        settings.enableDailyCycleMode = true
        settings.breakfastHour = 8;  settings.breakfastMinute = 0
        settings.lunchHour = 13;     settings.lunchMinute = 0
        settings.dinnerHour = 19;    settings.dinnerMinute = 0
        settings.bedtimeHour = 22;   settings.bedtimeMinute = 0
        let calendar = Calendar.current
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 16, hour: 12, minute: 30)))
        // lunch day (step 1): anchor = today - 1
        settings.dailyCycleAnchorDate = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: today))

        let settingsRepository = SpyCycleSettingsRepository(settings: settings)
        let sut = RescheduleGlucoseCycleUseCase(
            settingsRepository: settingsRepository,
            analyticsRepository: MockAnalyticsRepository()
        )

        let shifted = await sut.setTodayTarget(.dinner, today: today)

        XCTAssertTrue(shifted)
        // Anchor updated so today = dinnerDay (step 2): anchor = today - 2 days.
        let expectedAnchor = calendar.date(byAdding: .day, value: -2, to: calendar.startOfDay(for: today))
        XCTAssertEqual(settings.dailyCycleAnchorDate, expectedAnchor)
        XCTAssertEqual(settingsRepository.saveCount, 1)
    }

    func test_setTodayTarget_rescheduleTodayFromLunchToDinner_tomorrowIsBedtime() async throws {
        // Regression: rescheduling today must propagate to subsequent days.
        let settings = UserSettings.default()
        settings.enableDailyCycleMode = true
        settings.bedtimeSlotEnabled = true
        let calendar = Calendar.current
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 16, hour: 12, minute: 30)))
        // lunch day (step 1): anchor = today - 1
        settings.dailyCycleAnchorDate = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: today))

        let sut = RescheduleGlucoseCycleUseCase(
            settingsRepository: SpyCycleSettingsRepository(settings: settings),
            analyticsRepository: MockAnalyticsRepository()
        )

        let shifted = await sut.setTodayTarget(.dinner, today: today)
        XCTAssertTrue(shifted)

        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: today))
        let tomorrowTarget = await sut.currentTarget(today: tomorrow)
        XCTAssertEqual(tomorrowTarget, MealSlot.none) // bedtime follows dinner
    }

    func test_setTodayTarget_bedtimeDisabled_rejectsBedtimeSlot() async throws {
        let settings = UserSettings.default()
        settings.enableDailyCycleMode = true
        settings.bedtimeSlotEnabled = false
        let calendar = Calendar.current
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 16, hour: 12, minute: 30)))
        settings.dailyCycleAnchorDate = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: today))

        let settingsRepository = SpyCycleSettingsRepository(settings: settings)
        let sut = RescheduleGlucoseCycleUseCase(
            settingsRepository: settingsRepository,
            analyticsRepository: MockAnalyticsRepository()
        )

        let shifted = await sut.setTodayTarget(.none, today: today)
        XCTAssertFalse(shifted)
        XCTAssertEqual(settingsRepository.saveCount, 0)
    }

    func test_setTodayTarget_returnsFalseForCurrentSlot() async throws {
        let settings = UserSettings.default()
        settings.enableDailyCycleMode = true
        settings.breakfastHour = 8;  settings.breakfastMinute = 0
        settings.lunchHour = 13;     settings.lunchMinute = 0
        settings.dinnerHour = 19;    settings.dinnerMinute = 0
        settings.bedtimeHour = 22;   settings.bedtimeMinute = 0
        let calendar = Calendar.current
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 16, hour: 20, minute: 30)))
        // lunch day (step 1): anchor = today - 1
        settings.dailyCycleAnchorDate = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: today))

        let settingsRepository = SpyCycleSettingsRepository(settings: settings)
        let sut = RescheduleGlucoseCycleUseCase(
            settingsRepository: settingsRepository,
            analyticsRepository: MockAnalyticsRepository()
        )

        let shifted = await sut.setTodayTarget(.lunch, today: today)

        XCTAssertFalse(shifted)
        XCTAssertEqual(settingsRepository.saveCount, 0)
    }
}

@MainActor
private final class SpyCycleSettingsRepository: SettingsRepository {
    var settings: UserSettings
    private(set) var saveCount: Int = 0

    init(settings: UserSettings) {
        self.settings = settings
    }

    func getOrCreate() async throws -> UserSettings {
        settings
    }

    func save(_ settings: UserSettings) async throws {
        saveCount += 1
        self.settings = settings
    }

    func update(_ settings: UserSettings) async throws {
        self.settings = settings
    }
}
