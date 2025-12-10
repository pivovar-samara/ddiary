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
}

// MARK: - NotificationsRepository

/// Sendable infrastructure repository for scheduling and managing local notifications.
/// Operates purely on value types/DTOs and does not depend on SwiftData models.
public protocol NotificationsRepository: Sendable {
    /// Request authorization for notifications. Returns the current authorization state.
    func requestAuthorization() async throws -> Bool

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

    /// Cancel all scheduled notifications (BP and Glucose).
    func cancelAll() async
}

// MARK: - AnalyticsRepository

/// Sendable infrastructure repository for analytics logging.
public protocol AnalyticsRepository: Sendable {
    /// App launched/opened event.
    func logAppOpen() async

    /// A measurement was logged by the user.
    func logMeasurementLogged(kind: AnalyticsMeasurementKind) async

    /// Schedule settings were updated.
    func logScheduleUpdated(kind: AnalyticsScheduleKind) async

    /// CSV export occurred.
    func logExportCSV() async

    /// Google Sheets sync success.
    func logGoogleSyncSuccess() async

    /// Google Sheets sync failure with an optional reason.
    func logGoogleSyncFailure(reason: String?) async

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
}
