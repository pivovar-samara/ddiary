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

    private func makeViewModel(
        measurements: MockMeasurementsRepository,
        settings: MockSettingsRepository,
        notifications: SpyNotificationsRepository
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
            schedulesUpdater: NoopSchedulesUpdater(),
            notificationsRepository: notifications
        )
    }
}

@MainActor
private final class NoopSchedulesUpdater: SchedulesUpdating {
    func scheduleFromCurrentSettings() async throws {}
}

private final class SpyNotificationsRepository: NotificationsRepository, @unchecked Sendable {
    struct CanceledGlucoseSlot: Sendable, Equatable {
        let measurementType: GlucoseMeasurementType
        let date: Date
    }

    private(set) var canceledBPDates: [Date] = []
    private(set) var canceledGlucose: [CanceledGlucoseSlot] = []

    func requestAuthorization() async throws -> Bool { true }

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
        enableBedtime: Bool,
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
        categoryIdentifier: String
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
