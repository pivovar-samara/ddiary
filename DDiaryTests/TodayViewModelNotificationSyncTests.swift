import XCTest
@testable import DDiary

@MainActor
final class TodayViewModelNotificationSyncTests: XCTestCase {
    func test_refresh_cancelsNotificationsForCompletedTodaySlots() async throws {
        let measurements = MockMeasurementsRepository()
        let settings = MockSettingsRepository()
        let notifications = SpyNotificationsRepository()
        let calendar = Calendar.current
        let now = Date()
        let nowComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: now)
        let plannedDate = try XCTUnwrap(calendar.date(from: nowComponents))
        let minuteOfDay = (nowComponents.hour ?? 0) * 60 + (nowComponents.minute ?? 0)
        let weekday = calendar.component(.weekday, from: now)

        let userSettings = try await settings.getOrCreate()
        userSettings.enableDailyCycleMode = false
        userSettings.bpTimes = [minuteOfDay, (minuteOfDay + 1) % (24 * 60)]
        userSettings.bpActiveWeekdays = [weekday]
        userSettings.enableBeforeMeal = false
        userSettings.enableAfterMeal2h = false
        userSettings.bedtimeSlotEnabled = true
        userSettings.bedtimeHour = nowComponents.hour ?? 0
        userSettings.bedtimeMinute = nowComponents.minute ?? 0

        try await measurements.insertBP(
            BPMeasurement(
                id: UUID(),
                timestamp: plannedDate,
                systolic: 120,
                diastolic: 80,
                pulse: 70
            )
        )
        try await measurements.insertGlucose(
            GlucoseMeasurement(
                id: UUID(),
                timestamp: plannedDate,
                value: 5.5,
                unit: .mmolL,
                measurementType: .bedtime,
                mealSlot: .none,
                comment: nil
            )
        )

        let viewModel = makeViewModel(
            measurements: measurements,
            settings: settings,
            notifications: notifications
        )

        await viewModel.refresh()

        XCTAssertEqual(notifications.canceledBPDates.count, 1)
        XCTAssertTrue(calendar.isDate(notifications.canceledBPDates[0], equalTo: plannedDate, toGranularity: .minute))
        XCTAssertEqual(notifications.canceledGlucose.count, 1)
        XCTAssertEqual(notifications.canceledGlucose[0].measurementType, .bedtime)
        XCTAssertTrue(calendar.isDate(notifications.canceledGlucose[0].date, equalTo: plannedDate, toGranularity: .minute))
    }

    func test_refresh_whenNoCompletedSlots_doesNotCancelNotifications() async throws {
        let measurements = MockMeasurementsRepository()
        let settings = MockSettingsRepository()
        let notifications = SpyNotificationsRepository()
        let calendar = Calendar.current
        let now = Date()
        let nowComponents = calendar.dateComponents([.hour, .minute], from: now)
        let minuteOfDay = (nowComponents.hour ?? 0) * 60 + (nowComponents.minute ?? 0)
        let weekday = calendar.component(.weekday, from: now)

        let userSettings = try await settings.getOrCreate()
        userSettings.enableDailyCycleMode = false
        userSettings.bpTimes = [minuteOfDay]
        userSettings.bpActiveWeekdays = [weekday]
        userSettings.enableBeforeMeal = false
        userSettings.enableAfterMeal2h = false
        userSettings.bedtimeSlotEnabled = true
        userSettings.bedtimeHour = nowComponents.hour ?? 0
        userSettings.bedtimeMinute = nowComponents.minute ?? 0

        let viewModel = makeViewModel(
            measurements: measurements,
            settings: settings,
            notifications: notifications
        )

        await viewModel.refresh()

        XCTAssertTrue(notifications.canceledBPDates.isEmpty)
        XCTAssertTrue(notifications.canceledGlucose.isEmpty)
    }

    func test_presentQuickEntryFromNotification_bloodPressureFallsBackToNearestSlotDate() async throws {
        let measurements = MockMeasurementsRepository()
        let settings = MockSettingsRepository()
        let notifications = SpyNotificationsRepository()

        let userSettings = try await settings.getOrCreate()
        userSettings.enableDailyCycleMode = false
        userSettings.bpTimes = [9 * 60]
        userSettings.bpActiveWeekdays = [1, 2, 3, 4, 5, 6, 7]
        userSettings.enableBeforeMeal = false
        userSettings.enableAfterMeal2h = false
        userSettings.bedtimeSlotEnabled = false

        let viewModel = makeViewModel(
            measurements: measurements,
            settings: settings,
            notifications: notifications
        )
        await viewModel.refresh()

        let expected = try XCTUnwrap(viewModel.bpSlots.first?.scheduledDate)

        let resolvedDate = viewModel.presentQuickEntryFromNotification(
            target: .bloodPressure,
            scheduledDate: nil
        )

        XCTAssertEqual(resolvedDate, expected)
        XCTAssertTrue(viewModel.presentBPQuickEntry)
    }

    func test_presentQuickEntryFromNotification_prefersProvidedScheduledDateForBloodPressure() async {
        let measurements = MockMeasurementsRepository()
        let settings = MockSettingsRepository()
        let notifications = SpyNotificationsRepository()
        let viewModel = makeViewModel(
            measurements: measurements,
            settings: settings,
            notifications: notifications
        )
        let providedDate = Date(timeIntervalSince1970: 1_770_700_800)

        let resolvedDate = viewModel.presentQuickEntryFromNotification(
            target: .bloodPressure,
            scheduledDate: providedDate
        )

        XCTAssertEqual(resolvedDate, providedDate)
        XCTAssertTrue(viewModel.presentBPQuickEntry)
    }

    func test_presentQuickEntryFromNotification_prefersProvidedScheduledDateForGlucose() async {
        let measurements = MockMeasurementsRepository()
        let settings = MockSettingsRepository()
        let notifications = SpyNotificationsRepository()
        let viewModel = makeViewModel(
            measurements: measurements,
            settings: settings,
            notifications: notifications
        )
        let providedDate = Date(timeIntervalSince1970: 1_770_700_860)

        let resolvedDate = viewModel.presentQuickEntryFromNotification(
            target: .glucose(mealSlot: .lunch, measurementType: .beforeMeal),
            scheduledDate: providedDate
        )

        XCTAssertEqual(resolvedDate, providedDate)
        XCTAssertTrue(viewModel.presentGlucoseQuickEntry)
    }

    func test_cycleSwitchTargets_inDailyCycleMode_areAvailableForBedtimeSlot() async throws {
        let measurements = MockMeasurementsRepository()
        let settings = MockSettingsRepository()
        let notifications = SpyNotificationsRepository()
        let calendar = Calendar.current
        let now = Date()

        let userSettings = try await settings.getOrCreate()
        userSettings.enableDailyCycleMode = true
        userSettings.bedtimeHour = 22
        userSettings.bedtimeMinute = 0
        userSettings.dailyCycleAnchorDate = calendar.date(
            byAdding: .day,
            value: -3,
            to: calendar.startOfDay(for: now)
        )
        userSettings.currentCycleIndex = 3

        let viewModel = makeViewModel(
            measurements: measurements,
            settings: settings,
            notifications: notifications
        )
        await viewModel.refresh()

        let bedtimeSlot = try XCTUnwrap(
            viewModel.glucoseSlots.first(where: { $0.measurementType == .bedtime })
        )
        let targets = viewModel.cycleSwitchTargets(for: bedtimeSlot)

        XCTAssertEqual(targets, [.breakfast, .lunch, .dinner])
    }

    func test_refreshIfNeeded_clearsErrorMessageSetByFailedCycleShift() async throws {
        let measurements = MockMeasurementsRepository()
        let settings = MockSettingsRepository()
        let notifications = SpyNotificationsRepository()
        let calendar = Calendar.current
        let now = Date()

        let userSettings = try await settings.getOrCreate()
        userSettings.enableDailyCycleMode = true
        userSettings.dailyCycleAnchorDate = calendar.startOfDay(for: now)
        userSettings.currentCycleIndex = 0

        let throwingUpdater = ThrowingSchedulesUpdater()
        let viewModel = makeViewModel(
            measurements: measurements,
            settings: settings,
            notifications: notifications,
            schedulesUpdater: throwingUpdater
        )
        await viewModel.refresh()

        // Shift fails to reschedule notifications → sets errorMessage, then calls refresh() internally
        await viewModel.shiftCycleDayForward()

        // Explicit refreshIfNeeded must clear any residual errorMessage
        await viewModel.refreshIfNeeded(reason: .manual)

        XCTAssertNil(viewModel.errorMessage)
    }

    func test_switchDailyCycleTarget_postsExternalSettingsChangeNotification() async throws {
        let measurements = MockMeasurementsRepository()
        let settings = MockSettingsRepository()
        let notifications = SpyNotificationsRepository()
        let calendar = Calendar.current
        let now = Date()

        let userSettings = try await settings.getOrCreate()
        userSettings.enableDailyCycleMode = true
        userSettings.dailyCycleAnchorDate = calendar.startOfDay(for: now)
        userSettings.currentCycleIndex = 0

        let viewModel = makeViewModel(
            measurements: measurements,
            settings: settings,
            notifications: notifications
        )
        await viewModel.refresh()
        let target = try XCTUnwrap(viewModel.availableCycleSwitchTargets.first)

        let expectation = expectation(forNotification: .settingsDidChangeOutsideSettings, object: nil)

        await viewModel.switchDailyCycleTarget(to: target)

        await fulfillment(of: [expectation], timeout: 2)
    }

    private func makeViewModel(
        measurements: MockMeasurementsRepository,
        settings: MockSettingsRepository,
        notifications: SpyNotificationsRepository,
        schedulesUpdater: (any SchedulesUpdating)? = nil
    ) -> TodayViewModel {
        let analytics = MockAnalyticsRepository()
        let getTodayOverviewUseCase = GetTodayOverviewUseCase(
            measurementsRepository: measurements,
            settingsRepository: settings
        )
        let logBPMeasurementUseCase = LogBPMeasurementUseCase(
            measurementsRepository: measurements,
            analyticsRepository: analytics
        )
        let logGlucoseMeasurementUseCase = LogGlucoseMeasurementUseCase(
            measurementsRepository: measurements,
            settingsRepository: settings,
            analyticsRepository: analytics
        )
        let rescheduleGlucoseCycleUseCase = RescheduleGlucoseCycleUseCase(
            settingsRepository: settings,
            analyticsRepository: analytics
        )

        return TodayViewModel(
            getTodayOverviewUseCase: getTodayOverviewUseCase,
            logBPMeasurementUseCase: logBPMeasurementUseCase,
            logGlucoseMeasurementUseCase: logGlucoseMeasurementUseCase,
            rescheduleGlucoseCycleUseCase: rescheduleGlucoseCycleUseCase,
            schedulesUpdater: schedulesUpdater ?? NoopSchedulesUpdater(),
            notificationsRepository: notifications
        )
    }
}

@MainActor
private final class NoopSchedulesUpdater: SchedulesUpdating {
    func scheduleFromCurrentSettings() async throws {}
}

@MainActor
private final class ThrowingSchedulesUpdater: SchedulesUpdating {
    func scheduleFromCurrentSettings() async throws {
        throw TestError.forced
    }
}

private final class SpyNotificationsRepository: NotificationsRepository, @unchecked Sendable {
    struct CanceledGlucoseSlot: Sendable, Equatable {
        let measurementType: GlucoseMeasurementType
        let date: Date
    }

    private(set) var canceledBPDates: [Date] = []
    private(set) var canceledGlucose: [CanceledGlucoseSlot] = []

    func requestAuthorization() async throws -> Bool { true }

    func hasPendingNotificationRequests() async -> Bool { false }

    func scheduleBloodPressure(times: [Int], activeWeekdays: Set<Int>) async throws {}

    func cancelBloodPressure() async {}

    func rescheduleBloodPressure(times: [Int], activeWeekdays: Set<Int>) async throws {}

    func scheduleGlucoseBeforeMeal(
        breakfast: DateComponents,
        lunch: DateComponents,
        dinner: DateComponents,
        isEnabled: Bool
    ) async throws {}

    func scheduleGlucoseAfterMeal2h(
        breakfast: DateComponents,
        lunch: DateComponents,
        dinner: DateComponents,
        isEnabled: Bool
    ) async throws {}

    func scheduleGlucoseBedtime(isEnabled: Bool, time: DateComponents?) async throws {}

    func cancelGlucose() async {}

    func rescheduleGlucose(
        breakfast: DateComponents,
        lunch: DateComponents,
        dinner: DateComponents,
        enableBeforeMeal: Bool,
        enableAfterMeal2h: Bool,
        bedtimeTime: DateComponents?
    ) async throws {}

    func rescheduleGlucoseCycle(
        configuration: GlucoseCycleConfiguration,
        startDate: Date,
        numberOfDays: Int
    ) async throws {}

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

    func cancelPlannedBloodPressureNotification(at scheduledDate: Date) async {
        canceledBPDates.append(scheduledDate)
    }

    func cancelPlannedGlucoseNotification(measurementType: GlucoseMeasurementType, at scheduledDate: Date) async {
        canceledGlucose.append(CanceledGlucoseSlot(measurementType: measurementType, date: scheduledDate))
    }

    func scheduledReminders(on day: Date) async -> [ScheduledReminder] { [] }

    func cancelAll() async {}
}
