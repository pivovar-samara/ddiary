import Foundation

// MARK: - MeasurementsRepository

/// MainActor-bound repository for creating, updating, deleting, and querying measurements.
/// Operates on SwiftData `@Model` types and must be used on the main actor.
@MainActor
public protocol MeasurementsRepository {
    // MARK: Blood Pressure (BP)

    /// Insert a new BP measurement.
    func insertBP(_ measurement: BPMeasurement) async throws

    /// Update an existing BP measurement.
    func updateBP(_ measurement: BPMeasurement) async throws

    /// Delete a BP measurement.
    func deleteBP(_ measurement: BPMeasurement) async throws

    /// Fetch a BP measurement by identifier.
    func bpMeasurement(id: UUID) async throws -> BPMeasurement?

    /// Fetch BP measurements within a date range [from, to].
    func bpMeasurements(from: Date, to: Date) async throws -> [BPMeasurement]

    /// Fetch BP measurements with pending or failed Google sync status.
    func pendingOrFailedBPSync() async throws -> [BPMeasurement]

    // MARK: Glucose

    /// Insert a new Glucose measurement.
    func insertGlucose(_ measurement: GlucoseMeasurement) async throws

    /// Update an existing Glucose measurement.
    func updateGlucose(_ measurement: GlucoseMeasurement) async throws

    /// Delete a Glucose measurement.
    func deleteGlucose(_ measurement: GlucoseMeasurement) async throws

    /// Fetch a Glucose measurement by identifier.
    func glucoseMeasurement(id: UUID) async throws -> GlucoseMeasurement?

    /// Fetch Glucose measurements within a date range [from, to].
    func glucoseMeasurements(from: Date, to: Date) async throws -> [GlucoseMeasurement]

    /// Fetch Glucose measurements with pending or failed Google sync status.
    func pendingOrFailedGlucoseSync() async throws -> [GlucoseMeasurement]
}

// MARK: - SettingsRepository

/// MainActor-bound repository for accessing and persisting `UserSettings`.
@MainActor
public protocol SettingsRepository {
    /// Returns the existing `UserSettings` or creates a default one if absent.
    func getOrCreate() async throws -> UserSettings

    /// Persist changes to `UserSettings`.
    func save(_ settings: UserSettings) async throws

    /// Explicitly trigger an update/save cycle for `UserSettings`.
    /// Implementations may treat this the same as `save`.
    func update(_ settings: UserSettings) async throws
}

// MARK: - GoogleIntegrationRepository

/// MainActor-bound repository for accessing and updating Google Sheets integration state.
@MainActor
public protocol GoogleIntegrationRepository {
    /// Returns the existing `GoogleIntegration` or creates one if absent.
    func getOrCreate() async throws -> GoogleIntegration

    /// Persist changes to `GoogleIntegration`.
    func save(_ integration: GoogleIntegration) async throws

    /// Update an existing `GoogleIntegration`.
    func update(_ integration: GoogleIntegration) async throws

    /// Clear tokens and disable integration on logout.
    func clearTokens(_ integration: GoogleIntegration) async throws

    /// Read the stored Google OAuth refresh token from the Keychain.
    func getRefreshToken() async throws -> String?

    /// Write or delete the Google OAuth refresh token in the Keychain.
    /// Passing `nil` deletes any stored token.
    func setRefreshToken(_ token: String?) async throws
}

// MARK: - NotificationsRepository

public struct ScheduledReminder: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case bloodPressure
        case glucose(mealSlot: MealSlot, measurementType: GlucoseMeasurementType)
    }

    public let kind: Kind
    public let date: Date

    public init(kind: Kind, date: Date) {
        self.kind = kind
        self.date = date
    }
}

/// Sendable infrastructure repository for scheduling and managing local notifications.
/// Operates purely on value types/DTOs and does not depend on SwiftData models.
public protocol NotificationsRepository: Sendable {
    /// Request authorization for notifications. Returns the current authorization state.
    func requestAuthorization() async throws -> Bool

    /// Returns `true` when there are pending user-triggered one-off requests that should be preserved.
    /// Used to avoid destructive startup rescheduling that would remove snoozed/shifted reminders.
    func hasPendingNotificationRequests() async -> Bool

    // MARK: Blood Pressure scheduling

    /// Schedule repeating notifications for blood pressure times.
    /// - Parameters:
    ///   - times: Minutes since midnight for each desired reminder time (e.g., 9:00 -> 540).
    ///   - activeWeekdays: Weekday indices (1...7) to schedule on.
    func scheduleBloodPressure(times: [Int], activeWeekdays: Set<Int>) async throws

    /// Cancel all scheduled BP notifications.
    func cancelBloodPressure() async

    /// Reschedule BP notifications by cancelling existing ones and scheduling the provided set.
    func rescheduleBloodPressure(times: [Int], activeWeekdays: Set<Int>) async throws

    // MARK: Glucose scheduling

    /// Schedule before-meal glucose notifications for breakfast, lunch, and dinner.
    func scheduleGlucoseBeforeMeal(breakfast: DateComponents, lunch: DateComponents, dinner: DateComponents, isEnabled: Bool) async throws

    /// Schedule after-meal (2h) glucose notifications for breakfast, lunch, and dinner.
    func scheduleGlucoseAfterMeal2h(breakfast: DateComponents, lunch: DateComponents, dinner: DateComponents, isEnabled: Bool) async throws

    /// Schedule bedtime glucose notification.
    func scheduleGlucoseBedtime(isEnabled: Bool, time: DateComponents?) async throws

    /// Cancel all scheduled glucose notifications (before, after, bedtime).
    func cancelGlucose() async

    /// Reschedule glucose notifications by cancelling existing ones and scheduling the provided set.
    func rescheduleGlucose(
        breakfast: DateComponents,
        lunch: DateComponents,
        dinner: DateComponents,
        enableBeforeMeal: Bool,
        enableAfterMeal2h: Bool,
        enableBedtime: Bool,
        bedtimeTime: DateComponents?
    ) async throws

    /// Reschedule glucose notifications in a fixed 4-day cycle:
    /// breakfast+2h, lunch+2h, dinner+2h, bedtime, then repeat.
    func rescheduleGlucoseCycle(
        configuration: GlucoseCycleConfiguration,
        startDate: Date,
        numberOfDays: Int
    ) async throws

    // MARK: One-off helpers for actions (snooze/cancel by id)
    /// Schedule a one-off notification at a specific date (non-repeating).
    func scheduleOneOff(
        at date: Date,
        identifier: String,
        title: String,
        body: String,
        categoryIdentifier: String,
        userInfo: [AnyHashable: Any]
    ) async

    /// Convenience for snoozing: schedule a one-off notification after N minutes.
    func snooze(
        originalIdentifier: String,
        minutes: Int,
        title: String,
        body: String,
        categoryIdentifier: String,
        mealSlotRawValue: String?,
        measurementTypeRawValue: String?
    ) async

    /// Cancel a specific notification by identifier (pending and delivered).
    func cancel(withIdentifier id: String) async

    /// Mark a planned BP slot as completed by removing matching pending and delivered notifications.
    func cancelPlannedBloodPressureNotification(at scheduledDate: Date) async

    /// Mark a planned glucose slot as completed.
    /// Removes matching one-off/repeating pending and delivered reminders.
    func cancelPlannedGlucoseNotification(measurementType: GlucoseMeasurementType, at scheduledDate: Date) async

    /// Returns reminders that are currently pending or delivered for the specified calendar day.
    /// Used by Today screen computation to stay aligned with real notification state.
    func scheduledReminders(on day: Date) async -> [ScheduledReminder]

    /// Cancel all scheduled notifications (BP and Glucose).
    func cancelAll() async
}

// MARK: - Convenience APIs from UserSettings (MainActor-only)
@MainActor
public extension NotificationsRepository {
    /// Convenience: Reschedule all BP notifications using the provided settings model.
    /// Extracts only value data from `UserSettings` on the main actor and forwards
    /// to the granular scheduling API to avoid sending `@Model` instances across actors.
    func scheduleBPNotifications(settings: UserSettings) async throws {
        try await rescheduleBloodPressure(
            times: settings.bpTimes,
            activeWeekdays: settings.bpActiveWeekdays
        )
    }

    /// Convenience: Reschedule all Glucose notifications using the provided settings model.
    /// Uses meal times and feature toggles from `UserSettings`.
    func scheduleGlucoseNotifications(settings: UserSettings) async throws {
        let breakfast = DateComponents(hour: settings.breakfastHour, minute: settings.breakfastMinute)
        let lunch = DateComponents(hour: settings.lunchHour, minute: settings.lunchMinute)
        let dinner = DateComponents(hour: settings.dinnerHour, minute: settings.dinnerMinute)
        let bedtime = DateComponents(hour: settings.bedtimeHour, minute: settings.bedtimeMinute)

        if settings.enableDailyCycleMode {
            let anchorDate = settings.dailyCycleAnchorDate
                ?? GlucoseCyclePlanner.fallbackAnchorDate(currentCycleIndex: settings.currentCycleIndex)
            let configuration = GlucoseCycleConfiguration(
                anchorDate: anchorDate,
                breakfast: breakfast,
                lunch: lunch,
                dinner: dinner,
                bedtime: bedtime
            )
            try await rescheduleGlucoseCycle(
                configuration: configuration,
                startDate: Date(),
                numberOfDays: 28
            )
        } else {
            // Use the user-configured bedtime time when the slot and reminders are enabled.
            let bedtimeEnabled = settings.enableBedtime && settings.bedtimeSlotEnabled
            let bedtimeTime: DateComponents? = bedtimeEnabled ? bedtime : nil
            try await rescheduleGlucose(
                breakfast: breakfast,
                lunch: lunch,
                dinner: dinner,
                enableBeforeMeal: settings.enableBeforeMeal,
                enableAfterMeal2h: settings.enableAfterMeal2h,
                enableBedtime: bedtimeEnabled,
                bedtimeTime: bedtimeTime
            )
        }
    }

    /// Convenience: Cancel all pending notifications (BP and Glucose).
    func cancelAllNotifications() async {
        await cancelAll()
    }

    /// When a before-meal measurement is logged off schedule, shift today's paired
    /// after-meal (2h) reminder from the original planned time to the new +2h time.
    func rescheduleShiftedAfterMeal2hNotification(
        mealSlot: MealSlot,
        originalAfterDate: Date,
        shiftedAfterDate: Date
    ) async {
        guard mealSlot != .none else { return }
        guard shiftedAfterDate > Date() else { return }
        guard abs(shiftedAfterDate.timeIntervalSince(originalAfterDate)) >= 60 else { return }

        await cancelPlannedGlucoseNotification(measurementType: .afterMeal2h, at: originalAfterDate)

        let payload: (title: String, body: String)
        switch mealSlot {
        case .breakfast:
            payload = (L10n.notificationGlucoseAfterBreakfast2hTitle, L10n.notificationGlucoseAfterBreakfast2hBody)
        case .lunch:
            payload = (L10n.notificationGlucoseAfterLunch2hTitle, L10n.notificationGlucoseAfterLunch2hBody)
        case .dinner:
            payload = (L10n.notificationGlucoseAfterDinner2hTitle, L10n.notificationGlucoseAfterDinner2hBody)
        case .none:
            return
        }

        let calendar = Calendar.current
        let identifier = shiftedAfterMealIdentifier(mealSlot: mealSlot, date: shiftedAfterDate, calendar: calendar)
        await cancel(withIdentifier: identifier)
        await scheduleOneOff(
            at: shiftedAfterDate,
            identifier: identifier,
            title: payload.title,
            body: payload.body,
            categoryIdentifier: UserNotificationsRepository.IDs.glucoseAfterCategory,
            userInfo: [
                UserNotificationsRepository.PayloadKeys.mealSlot: mealSlot.rawValue,
                UserNotificationsRepository.PayloadKeys.measurementType: GlucoseMeasurementType.afterMeal2h.rawValue,
            ]
        )
    }

    /// Convenience: Cancel everything and schedule both BP and Glucose from settings.
    /// Call this after saving settings or after first authorization is granted.
    func scheduleAllNotifications(settings: UserSettings) async throws {
        await cancelAll()
        try await scheduleBPNotifications(settings: settings)
        try await scheduleGlucoseNotifications(settings: settings)
    }

    /// Schedules a debug-only BP notification that matches production category/content.
    func scheduleDebugBloodPressureNotification(after seconds: TimeInterval = 10) async {
        let date = Date().addingTimeInterval(seconds)
        let identifier = "ddiary.debug.bp.\(Int(date.timeIntervalSince1970))"
        await scheduleOneOff(
            at: date,
            identifier: identifier,
            title: L10n.notificationBPTitle,
            body: L10n.notificationBPBody,
            categoryIdentifier: UserNotificationsRepository.IDs.bpCategory,
            userInfo: [:]
        )
    }

    /// Schedules a debug-only Glucose notification that matches production category/content.
    func scheduleDebugGlucoseNotification(after seconds: TimeInterval = 10) async {
        let date = Date().addingTimeInterval(seconds)
        let identifier = "ddiary.debug.glucose.before.breakfast.\(Int(date.timeIntervalSince1970))"
        await scheduleOneOff(
            at: date,
            identifier: identifier,
            title: L10n.notificationGlucoseBeforeBreakfastTitle,
            body: L10n.notificationGlucoseBeforeBreakfastBody,
            categoryIdentifier: UserNotificationsRepository.IDs.glucoseBeforeCategory,
            userInfo: [
                UserNotificationsRepository.PayloadKeys.mealSlot: MealSlot.breakfast.rawValue,
                UserNotificationsRepository.PayloadKeys.measurementType: GlucoseMeasurementType.beforeMeal.rawValue,
            ]
        )
    }

    private func shiftedAfterMealIdentifier(mealSlot: MealSlot, date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let year = parts.year ?? 0
        let month = parts.month ?? 0
        let day = parts.day ?? 0
        let hour = parts.hour ?? 0
        let minute = parts.minute ?? 0
        return "\(UserNotificationsRepository.IDs.glucoseAfterPrefix)shifted.\(mealSlot.rawValue).d\(String(format: "%04d", year))\(String(format: "%02d", month))\(String(format: "%02d", day)).\(String(format: "%02d", hour))\(String(format: "%02d", minute))"
    }
}

// MARK: - AnalyticsRepository

/// Sendable infrastructure repository for analytics logging.
public protocol AnalyticsRepository: Sendable {
    /// App launched/opened event.
    func logAppOpen() async

    /// A measurement was logged by the user.
    func logMeasurementLogged(kind: AnalyticsMeasurementKind) async

    /// A measurement save attempt failed.
    func logMeasurementSaveFailed(kind: AnalyticsMeasurementKind, reason: String?) async

    /// Schedule settings were updated.
    func logScheduleUpdated(kind: AnalyticsScheduleKind) async

    /// Schedule update failed.
    func logScheduleUpdateFailed(kind: AnalyticsScheduleKind, reason: String?) async

    /// CSV export occurred.
    func logExportCSV() async

    /// Google Sheets sync success.
    func logGoogleSyncSuccess() async

    /// Google Sheets sync failure with an optional reason.
    func logGoogleSyncFailure(reason: String?) async

    /// Google Sheets sync finished summary.
    func logGoogleSyncFinished(successCount: Int, failureCount: Int) async

    /// Google Sheets integration enabled.
    func logGoogleEnabled() async

    /// Google Sheets integration disabled.
    func logGoogleDisabled() async
}

// MARK: - Analytics helper enums

public enum AnalyticsMeasurementKind: Sendable {
    case bloodPressure
    case glucose
}

public enum AnalyticsScheduleKind: Sendable {
    case bloodPressure
    case glucose
}

// MARK: - GoogleSheetsClient

public struct GoogleSheetsCredentials: Sendable {
    public let spreadsheetId: String
    public let refreshToken: String
    public let googleUserId: String?

    public init(spreadsheetId: String, refreshToken: String, googleUserId: String?) {
        self.spreadsheetId = spreadsheetId
        self.refreshToken = refreshToken
        self.googleUserId = googleUserId
    }
}

public struct GoogleSheetsBPRow: Sendable {
    public let id: UUID
    public let timestamp: Date
    public let systolic: Int
    public let diastolic: Int
    public let pulse: Int
    public let comment: String?

    public init(
        id: UUID,
        timestamp: Date,
        systolic: Int,
        diastolic: Int,
        pulse: Int,
        comment: String?
    ) {
        self.id = id
        self.timestamp = timestamp
        self.systolic = systolic
        self.diastolic = diastolic
        self.pulse = pulse
        self.comment = comment
    }
}

public struct GoogleSheetsGlucoseRow: Sendable {
    public let id: UUID
    public let timestamp: Date
    public let value: Double
    public let unit: GlucoseUnit
    public let measurementType: GlucoseMeasurementType
    public let mealSlot: MealSlot
    public let comment: String?

    public init(
        id: UUID,
        timestamp: Date,
        value: Double,
        unit: GlucoseUnit,
        measurementType: GlucoseMeasurementType,
        mealSlot: MealSlot,
        comment: String?
    ) {
        self.id = id
        self.timestamp = timestamp
        self.value = value
        self.unit = unit
        self.measurementType = measurementType
        self.mealSlot = mealSlot
        self.comment = comment
    }
}

public protocol GoogleSheetsClient: Sendable {
    func appendBloodPressureRow(_ row: GoogleSheetsBPRow, credentials: GoogleSheetsCredentials) async throws
    func appendGlucoseRow(_ row: GoogleSheetsGlucoseRow, credentials: GoogleSheetsCredentials) async throws
    /// Updates an existing row if the id is present, otherwise appends a new row.
    func upsertBloodPressureRow(_ row: GoogleSheetsBPRow, credentials: GoogleSheetsCredentials) async throws
    /// Updates an existing row if the id is present, otherwise appends a new row.
    func upsertGlucoseRow(_ row: GoogleSheetsGlucoseRow, credentials: GoogleSheetsCredentials) async throws
    /// Ensures spreadsheet sheets and header rows exist.
    func ensureSheetsAndHeaders(credentials: GoogleSheetsCredentials) async throws

    /// Returns an existing spreadsheet id for the provided title, or nil when none are found.
    /// Implementations should use the provided refresh token to obtain an access token.
    func findSpreadsheetIdByTitle(refreshToken: String, title: String) async throws -> String?

    /// Creates a new Google Spreadsheet with required sheets and header rows and returns its `spreadsheetId`.
    /// Implementations should use the provided refresh token to obtain an access token.
    func createSpreadsheetAndSetup(refreshToken: String, title: String) async throws -> String
}

public enum GoogleSheetsClientProtocolError: Error { case unimplemented }

public extension GoogleSheetsClient {
    func upsertBloodPressureRow(_ row: GoogleSheetsBPRow, credentials: GoogleSheetsCredentials) async throws {
        try await appendBloodPressureRow(row, credentials: credentials)
    }

    func upsertGlucoseRow(_ row: GoogleSheetsGlucoseRow, credentials: GoogleSheetsCredentials) async throws {
        try await appendGlucoseRow(row, credentials: credentials)
    }

    func ensureSheetsAndHeaders(credentials: GoogleSheetsCredentials) async throws {
        // Default no-op for non-live implementations.
    }

    func findSpreadsheetIdByTitle(refreshToken: String, title: String) async throws -> String? {
        nil
    }

    func createSpreadsheetAndSetup(refreshToken: String, title: String) async throws -> String {
        throw GoogleSheetsClientProtocolError.unimplemented
    }
}
