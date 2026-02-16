import XCTest
@testable import DDiary

@MainActor
final class RescheduleGlucoseCycleUseCaseTests: XCTestCase {
    func test_advanceIfEnabled_movesToNextTargetAndLogsAnalytics() async throws {
        let settings = UserSettings.default()
        settings.enableDailyCycleMode = true
        settings.bedtimeSlotEnabled = false
        settings.currentCycleIndex = 0

        let settingsRepository = SpyCycleSettingsRepository(settings: settings)
        let analyticsRepository = MockAnalyticsRepository()
        let sut = RescheduleGlucoseCycleUseCase(
            settingsRepository: settingsRepository,
            analyticsRepository: analyticsRepository
        )

        await sut.advanceIfEnabled()

        XCTAssertEqual(settings.currentCycleIndex, 1)
        XCTAssertEqual(settingsRepository.saveCount, 1)
        XCTAssertEqual(analyticsRepository.scheduleUpdated, [.glucose])
    }

    func test_advanceIfEnabled_wrapsThroughBedtimeStepWhenEnabled() async {
        let settings = UserSettings.default()
        settings.enableDailyCycleMode = true
        settings.bedtimeSlotEnabled = true
        settings.currentCycleIndex = 2 // dinner

        let settingsRepository = SpyCycleSettingsRepository(settings: settings)
        let analyticsRepository = MockAnalyticsRepository()
        let sut = RescheduleGlucoseCycleUseCase(
            settingsRepository: settingsRepository,
            analyticsRepository: analyticsRepository
        )

        await sut.advanceIfEnabled()
        XCTAssertEqual(settings.currentCycleIndex, 3) // bedtime (.none)

        await sut.advanceIfEnabled()
        XCTAssertEqual(settings.currentCycleIndex, 0) // wraps to breakfast
    }

    func test_setTarget_ignoresWhenCycleModeDisabled() async {
        let settings = UserSettings.default()
        settings.enableDailyCycleMode = false
        settings.currentCycleIndex = 1

        let settingsRepository = SpyCycleSettingsRepository(settings: settings)
        let analyticsRepository = MockAnalyticsRepository()
        let sut = RescheduleGlucoseCycleUseCase(
            settingsRepository: settingsRepository,
            analyticsRepository: analyticsRepository
        )

        await sut.setTarget(.dinner)

        XCTAssertEqual(settings.currentCycleIndex, 1)
        XCTAssertEqual(settingsRepository.saveCount, 0)
        XCTAssertTrue(analyticsRepository.scheduleUpdated.isEmpty)
    }

    func test_currentTarget_handlesNegativeIndexByWrapping() async {
        let settings = UserSettings.default()
        settings.enableDailyCycleMode = true
        settings.currentCycleIndex = -1

        let settingsRepository = SpyCycleSettingsRepository(settings: settings)
        let analyticsRepository = MockAnalyticsRepository()
        let sut = RescheduleGlucoseCycleUseCase(
            settingsRepository: settingsRepository,
            analyticsRepository: analyticsRepository
        )

        let target = await sut.currentTarget()

        XCTAssertEqual(target, MealSlot.none)
    }

    func test_shiftTodayForward_movesAnchorBackwardAndRotatesTarget() async throws {
        let settings = UserSettings.default()
        settings.enableDailyCycleMode = true
        settings.currentCycleIndex = 0
        let calendar = Calendar.current
        let today = calendar.date(from: DateComponents(year: 2026, month: 2, day: 16, hour: 9, minute: 0)) ?? Date()
        settings.dailyCycleAnchorDate = calendar.startOfDay(for: today)

        let settingsRepository = SpyCycleSettingsRepository(settings: settings)
        let analyticsRepository = MockAnalyticsRepository()
        let sut = RescheduleGlucoseCycleUseCase(
            settingsRepository: settingsRepository,
            analyticsRepository: analyticsRepository
        )

        let shifted = await sut.shiftTodayForward(today: today)

        XCTAssertTrue(shifted)
        let shiftedAnchor = try XCTUnwrap(settings.dailyCycleAnchorDate)
        let expectedAnchor = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: today))
        XCTAssertEqual(shiftedAnchor, expectedAnchor)
        let target = await sut.currentTarget()
        XCTAssertEqual(target, .lunch)
    }

    func test_shiftTodayForward_returnsFalseWhenCycleModeDisabled() async {
        let settings = UserSettings.default()
        settings.enableDailyCycleMode = false
        settings.currentCycleIndex = 0
        settings.dailyCycleAnchorDate = Date(timeIntervalSince1970: 1_700_000_000)

        let settingsRepository = SpyCycleSettingsRepository(settings: settings)
        let analyticsRepository = MockAnalyticsRepository()
        let sut = RescheduleGlucoseCycleUseCase(
            settingsRepository: settingsRepository,
            analyticsRepository: analyticsRepository
        )

        let shifted = await sut.shiftTodayForward()

        XCTAssertFalse(shifted)
        XCTAssertEqual(settings.dailyCycleAnchorDate, Date(timeIntervalSince1970: 1_700_000_000))
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
