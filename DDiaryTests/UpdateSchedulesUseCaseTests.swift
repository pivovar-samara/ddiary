import XCTest
@testable import DDiary

// @MainActor: SpyNotificationsRepository and FixedSettingsRepository are main-actor-confined.
// Tests must run serially on the main actor to avoid data races on their mutable spy state.
@MainActor
final class UpdateSchedulesUseCaseTests: XCTestCase {
    func test_requestAuthorizationAndSchedule_whenGranted_reschedulesFromCurrentSettings() async {
        let settings = UserSettings.default()
        let settingsRepository = FixedSettingsRepository(settings: settings)
        let notificationsRepository = SpyNotificationsRepository()
        notificationsRepository.requestAuthorizationResult = true
        let analyticsRepository = MockAnalyticsRepository()
        let sut = UpdateSchedulesUseCase(
            settingsRepository: settingsRepository,
            notificationsRepository: notificationsRepository,
            analyticsRepository: analyticsRepository
        )

        await sut.requestAuthorizationAndSchedule()

        XCTAssertEqual(notificationsRepository.requestAuthorizationCallCount, 1)
        XCTAssertEqual(notificationsRepository.cancelAllExceptOneOffRequestsCount, 1)
    }

    func test_requestAuthorizationAndSchedule_withSnoozedPending_usesPreservingCancel() async {
        // scheduleAllNotifications must call cancelAllExceptOneOffRequests (not cancelAll),
        // so that any pending snooze/shifted notifications survive the startup reschedule.
        let settings = UserSettings.default()
        let settingsRepository = FixedSettingsRepository(settings: settings)
        let notificationsRepository = SpyNotificationsRepository()
        notificationsRepository.requestAuthorizationResult = true
        let analyticsRepository = MockAnalyticsRepository()
        let sut = UpdateSchedulesUseCase(
            settingsRepository: settingsRepository,
            notificationsRepository: notificationsRepository,
            analyticsRepository: analyticsRepository
        )

        await sut.requestAuthorizationAndSchedule()

        XCTAssertEqual(notificationsRepository.cancelAllExceptOneOffRequestsCount, 1,
            "scheduleAllNotifications must use the snooze-preserving cancel path")
        XCTAssertEqual(notificationsRepository.cancelAllCount, 0,
            "cancelAll must not be called directly — it would destroy snoozed notifications")
    }

    func test_scheduleFromCurrentSettings_reschedulesBloodPressure_withCorrectTimesAndWeekdays() async throws {
        let settings = UserSettings.default()
        settings.bpTimes = [540, 1260]
        settings.bpActiveWeekdays = [2, 4]

        let settingsRepository = FixedSettingsRepository(settings: settings)
        let notificationsRepository = SpyNotificationsRepository()
        let sut = UpdateSchedulesUseCase(
            settingsRepository: settingsRepository,
            notificationsRepository: notificationsRepository,
            analyticsRepository: MockAnalyticsRepository()
        )

        try await sut.scheduleFromCurrentSettings()

        XCTAssertEqual(notificationsRepository.cancelAllExceptOneOffRequestsCount, 1)
        XCTAssertEqual(notificationsRepository.bpTimes, [540, 1260])
        XCTAssertEqual(notificationsRepository.bpActiveWeekdays, [2, 4])
    }

    func test_scheduleFromCurrentSettings_reschedulesGlucose_withCorrectMealTimesAndFlags() async throws {
        let settings = UserSettings.default()
        settings.breakfastHour = 8
        settings.breakfastMinute = 15
        settings.lunchHour = 13
        settings.lunchMinute = 10
        settings.dinnerHour = 19
        settings.dinnerMinute = 45
        settings.enableBeforeMeal = true
        settings.enableAfterMeal2h = false
        settings.bedtimeSlotEnabled = true
        settings.bedtimeHour = 22
        settings.bedtimeMinute = 30

        let settingsRepository = FixedSettingsRepository(settings: settings)
        let notificationsRepository = SpyNotificationsRepository()
        let sut = UpdateSchedulesUseCase(
            settingsRepository: settingsRepository,
            notificationsRepository: notificationsRepository,
            analyticsRepository: MockAnalyticsRepository()
        )

        try await sut.scheduleFromCurrentSettings()

        XCTAssertEqual(notificationsRepository.glucoseBreakfast.hour, 8)
        XCTAssertEqual(notificationsRepository.glucoseBreakfast.minute, 15)
        XCTAssertEqual(notificationsRepository.glucoseLunch.hour, 13)
        XCTAssertEqual(notificationsRepository.glucoseDinner.hour, 19)
        XCTAssertEqual(notificationsRepository.enableBeforeMeal, true)
        XCTAssertEqual(notificationsRepository.enableAfterMeal2h, false)
        XCTAssertEqual(notificationsRepository.bedtimeTime?.hour, 22)
        XCTAssertEqual(notificationsRepository.bedtimeTime?.minute, 30)
    }

    func test_scheduleFromCurrentSettings_logsAnalyticsForBothKinds() async throws {
        let settingsRepository = FixedSettingsRepository(settings: UserSettings.default())
        let analyticsRepository = MockAnalyticsRepository()
        let sut = UpdateSchedulesUseCase(
            settingsRepository: settingsRepository,
            notificationsRepository: SpyNotificationsRepository(),
            analyticsRepository: analyticsRepository
        )

        try await sut.scheduleFromCurrentSettings()

        XCTAssertEqual(analyticsRepository.scheduleUpdated, [.bloodPressure, .glucose])
    }

    func test_scheduleFromCurrentSettings_disablesBedtimeWhenBedtimeSlotOff() async throws {
        let settings = UserSettings.default()
        settings.bedtimeSlotEnabled = false
        settings.bedtimeHour = 23
        settings.bedtimeMinute = 5

        let settingsRepository = FixedSettingsRepository(settings: settings)
        let notificationsRepository = SpyNotificationsRepository()
        let analyticsRepository = MockAnalyticsRepository()
        let sut = UpdateSchedulesUseCase(
            settingsRepository: settingsRepository,
            notificationsRepository: notificationsRepository,
            analyticsRepository: analyticsRepository
        )

        try await sut.scheduleFromCurrentSettings()

        XCTAssertNil(notificationsRepository.bedtimeTime)
    }

    func test_scheduleFromCurrentSettings_cycleMode_usesCycleScheduling() async throws {
        let settings = UserSettings.default()
        settings.enableDailyCycleMode = true
        settings.currentCycleIndex = 2
        settings.breakfastHour = 8
        settings.breakfastMinute = 0
        settings.lunchHour = 13
        settings.lunchMinute = 0
        settings.dinnerHour = 19
        settings.dinnerMinute = 0
        settings.bedtimeHour = 22
        settings.bedtimeMinute = 15

        let settingsRepository = FixedSettingsRepository(settings: settings)
        let notificationsRepository = SpyNotificationsRepository()
        // Pre-set to true so the assertions below are meaningful (not vacuous).
        notificationsRepository.enableBeforeMeal = true
        notificationsRepository.enableAfterMeal2h = true
        let analyticsRepository = MockAnalyticsRepository()
        let sut = UpdateSchedulesUseCase(
            settingsRepository: settingsRepository,
            notificationsRepository: notificationsRepository,
            analyticsRepository: analyticsRepository
        )

        try await sut.scheduleFromCurrentSettings()

        XCTAssertEqual(notificationsRepository.rescheduleGlucoseCycleCallCount, 1)
        XCTAssertNotNil(notificationsRepository.glucoseCycleConfiguration)
        XCTAssertEqual(notificationsRepository.glucoseCycleConfiguration?.dinner.hour, 19)
        XCTAssertEqual(notificationsRepository.glucoseCycleConfiguration?.bedtime.minute, 15)
        XCTAssertEqual(notificationsRepository.glucoseCycleNumberOfDays, 28)
        XCTAssertNotNil(settings.dailyCycleAnchorDate)
        // rescheduleGlucose must NOT have been called — cycle mode bypasses the standard path.
        XCTAssertEqual(notificationsRepository.enableBeforeMeal, true,
            "rescheduleGlucose was called unexpectedly — it must not run in cycle mode")
        XCTAssertEqual(notificationsRepository.enableAfterMeal2h, true,
            "rescheduleGlucose was called unexpectedly — it must not run in cycle mode")
    }

    func test_scheduleFromCurrentSettings_whenSettingsLoadFails_doesNotLogAnalytics() async {
        let settings = UserSettings.default()
        let settingsRepository = FixedSettingsRepository(settings: settings)
        settingsRepository.error = TestError.forced
        let notificationsRepository = SpyNotificationsRepository()
        let analyticsRepository = MockAnalyticsRepository()
        let sut = UpdateSchedulesUseCase(
            settingsRepository: settingsRepository,
            notificationsRepository: notificationsRepository,
            analyticsRepository: analyticsRepository
        )

        await XCTAssertThrowsErrorAsync(try await sut.scheduleFromCurrentSettings())

        XCTAssertEqual(notificationsRepository.cancelAllExceptOneOffRequestsCount, 0)
        XCTAssertTrue(analyticsRepository.scheduleUpdated.isEmpty)
        XCTAssertEqual(analyticsRepository.scheduleUpdateFailed.count, 2)
    }
}

@MainActor
private final class FixedSettingsRepository: SettingsRepository {
    var settings: UserSettings
    var error: Error?

    init(settings: UserSettings) {
        self.settings = settings
    }

    func getOrCreate() async throws -> UserSettings {
        if let error {
            throw error
        }
        return settings
    }

    func save(_ settings: UserSettings) async throws {
        self.settings = settings
    }

    func update(_ settings: UserSettings) async throws {
        self.settings = settings
    }
}

// @MainActor: all mutable state is confined to the main actor.
// Replacing @unchecked Sendable — actor isolation provides the same Sendable guarantee
// without suppressing the data-race checker.
@MainActor
private final class SpyNotificationsRepository: NotificationsRepository {
    var requestAuthorizationResult = true
    private(set) var requestAuthorizationCallCount = 0
    private(set) var cancelAllCount = 0
    private(set) var cancelAllExceptOneOffRequestsCount = 0
    private(set) var bpTimes: [Int] = []
    private(set) var bpActiveWeekdays: Set<Int> = []
    private(set) var glucoseBreakfast = DateComponents()
    private(set) var glucoseLunch = DateComponents()
    private(set) var glucoseDinner = DateComponents()
    // Mutable (not private(set)) so tests can pre-set values before the act step.
    var enableBeforeMeal = false
    var enableAfterMeal2h = false
    private(set) var bedtimeTime: DateComponents?
    private(set) var rescheduleGlucoseCycleCallCount = 0
    private(set) var glucoseCycleConfiguration: GlucoseCycleConfiguration?
    private(set) var glucoseCycleStartDate: Date?
    private(set) var glucoseCycleNumberOfDays: Int?

    func requestAuthorization() async throws -> Bool {
        requestAuthorizationCallCount += 1
        return requestAuthorizationResult
    }

    func hasPendingNotificationRequests() async -> Bool { false }

    func scheduleBloodPressure(times: [Int], activeWeekdays: Set<Int>) async throws {
        bpTimes = times
        bpActiveWeekdays = activeWeekdays
    }

    func cancelBloodPressure() async {}

    func rescheduleBloodPressure(times: [Int], activeWeekdays: Set<Int>) async throws {
        bpTimes = times
        bpActiveWeekdays = activeWeekdays
    }

    func scheduleGlucoseBeforeMeal(breakfast: DateComponents, lunch: DateComponents, dinner: DateComponents, isEnabled: Bool) async throws {}

    func scheduleGlucoseAfterMeal2h(breakfast: DateComponents, lunch: DateComponents, dinner: DateComponents, isEnabled: Bool) async throws {}

    func scheduleGlucoseBedtime(isEnabled: Bool, time: DateComponents?) async throws {}

    func cancelGlucose() async {}

    func rescheduleGlucose(
        breakfast: DateComponents,
        lunch: DateComponents,
        dinner: DateComponents,
        enableBeforeMeal: Bool,
        enableAfterMeal2h: Bool,
        bedtimeTime: DateComponents?
    ) async throws {
        glucoseBreakfast = breakfast
        glucoseLunch = lunch
        glucoseDinner = dinner
        self.enableBeforeMeal = enableBeforeMeal
        self.enableAfterMeal2h = enableAfterMeal2h
        self.bedtimeTime = bedtimeTime
    }

    func rescheduleGlucoseCycle(
        configuration: GlucoseCycleConfiguration,
        startDate: Date,
        numberOfDays: Int
    ) async throws {
        rescheduleGlucoseCycleCallCount += 1
        glucoseCycleConfiguration = configuration
        glucoseCycleStartDate = startDate
        glucoseCycleNumberOfDays = numberOfDays
    }

    func scheduleOneOff(
        at date: Date,
        identifier: String,
        title: String,
        body: String,
        categoryIdentifier: String,
        userInfo: [AnyHashable: Any]
    ) async {}

    func snooze(
        originalIdentifier: String,
        minutes: Int,
        title: String,
        body: String,
        categoryIdentifier: String,
        mealSlotRawValue: String?,
        measurementTypeRawValue: String?
    ) async {}

    func cancel(withIdentifier id: String) async {}

    func cancelPlannedBloodPressureNotification(at scheduledDate: Date) async {}

    func cancelPlannedGlucoseNotification(measurementType: GlucoseMeasurementType, at scheduledDate: Date) async {}

    func scheduledReminders(on day: Date) async -> [ScheduledReminder] { [] }

    func cancelAll() async {
        cancelAllCount += 1
    }

    func cancelAllExceptOneOffRequests() async {
        cancelAllExceptOneOffRequestsCount += 1
    }
}
