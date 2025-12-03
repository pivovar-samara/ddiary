import Foundation

// MARK: - No-op Analytics Repository

struct NoopAnalyticsRepository: AnalyticsRepository {
    func logAppOpen() async {}
    func logMeasurementLogged(kind: AnalyticsMeasurementKind) async {}
    func logScheduleUpdated(kind: AnalyticsScheduleKind) async {}
    func logExportCSV() async {}
    func logGoogleSyncSuccess() async {}
    func logGoogleSyncFailure(reason: String?) async {}
    func logGoogleEnabled() async {}
    func logGoogleDisabled() async {}
}

// MARK: - No-op User Notifications Repository

struct NoopUserNotificationsRepository: NotificationsRepository {
    func requestAuthorization() async throws -> Bool { true }

    func scheduleBloodPressure(times: [Int], activeWeekdays: Set<Int>) async throws {}
    func cancelBloodPressure() async {}
    func rescheduleBloodPressure(times: [Int], activeWeekdays: Set<Int>) async throws {}

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
        enableBedtime: Bool,
        bedtimeTime: DateComponents?
    ) async throws {}

    func cancelAll() async {}
}
