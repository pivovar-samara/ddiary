// RepositoryProtocols.swift
// Defines repository protocols to decouple domain/use case layer from infrastructure.

import Foundation

// MARK: - Supporting Types

/// Types of measurements supported by the app.
public enum MeasurementType: String, Sendable {
    case bloodPressure
    case glucose
}

/// Glucose reminder slots.
public enum GlucoseSlot: String, Sendable, CaseIterable {
    case beforeMeals
    case afterMeals
    case bedtime
}

// MARK: - MeasurementsRepository

@MainActor
/// Abstraction for CRUD and query operations over blood pressure and glucose measurements.
/// Implementations may use SwiftData, Core Data, or any other persistence mechanism.
public protocol MeasurementsRepository {
    // MARK: BPMeasurement CRUD
    /// Creates a new blood pressure measurement.
    func createBPMeasurement(_ measurement: BPMeasurement) async throws -> BPMeasurement

    /// Fetches a single blood pressure measurement by identifier.
    func getBPMeasurement(id: UUID) async throws -> BPMeasurement?

    /// Updates an existing blood pressure measurement.
    func updateBPMeasurement(_ measurement: BPMeasurement) async throws -> BPMeasurement

    /// Deletes a blood pressure measurement by identifier.
    func deleteBPMeasurement(id: UUID) async throws

    // MARK: GlucoseMeasurement CRUD
    /// Creates a new glucose measurement.
    func createGlucoseMeasurement(_ measurement: GlucoseMeasurement) async throws -> GlucoseMeasurement

    /// Fetches a single glucose measurement by identifier.
    func getGlucoseMeasurement(id: UUID) async throws -> GlucoseMeasurement?

    /// Updates an existing glucose measurement.
    func updateGlucoseMeasurement(_ measurement: GlucoseMeasurement) async throws -> GlucoseMeasurement

    /// Deletes a glucose measurement by identifier.
    func deleteGlucoseMeasurement(id: UUID) async throws

    // MARK: Queries by type
    /// Returns all blood pressure measurements.
    func fetchAllBloodPressureMeasurements() async throws -> [BPMeasurement]

    /// Returns all glucose measurements.
    func fetchAllGlucoseMeasurements() async throws -> [GlucoseMeasurement]

    // MARK: Queries by date range
    /// Returns blood pressure measurements within the specified date range (inclusive of bounds).
    func fetchBloodPressureMeasurements(from startDate: Date, to endDate: Date) async throws -> [BPMeasurement]

    /// Returns glucose measurements within the specified date range (inclusive of bounds).
    func fetchGlucoseMeasurements(from startDate: Date, to endDate: Date) async throws -> [GlucoseMeasurement]

    // MARK: Google Sync
    /// Returns blood pressure measurements that are pending or failed for Google sync.
    func fetchBloodPressureMeasurementsNeedingGoogleSync() async throws -> [BPMeasurement]

    /// Returns glucose measurements that are pending or failed for Google sync.
    func fetchGlucoseMeasurementsNeedingGoogleSync() async throws -> [GlucoseMeasurement]
}

// MARK: - SettingsRepository

@MainActor
/// Abstraction over user settings persistence.
public protocol SettingsRepository {
    /// Returns the existing settings or creates a default one if missing.
    func getOrCreateUserSettings() async throws -> UserSettings

    /// Persists updates to user settings and returns the saved value.
    func updateUserSettings(_ settings: UserSettings) async throws -> UserSettings
}

// MARK: - GoogleIntegrationRepository

@MainActor
/// Abstraction over Google integration persistence and token lifecycle.
public protocol GoogleIntegrationRepository {
    /// Returns the existing integration or creates a default one if missing.
    func getOrCreateGoogleIntegration() async throws -> GoogleIntegration

    /// Persists updates to the Google integration and returns the saved value.
    func updateGoogleIntegration(_ integration: GoogleIntegration) async throws -> GoogleIntegration

    /// Clears any stored tokens/credentials (e.g., on user logout).
    func clearTokensOnLogout() async throws
}

// MARK: - NotificationsRepository

/// Abstraction over local notification scheduling and user actions.
public protocol NotificationsRepository {
    // MARK: Authorization
    /// Requests user authorization to send notifications. Returns the granted status.
    func requestAuthorization() async throws -> Bool

    // MARK: Scheduling
    /// Schedules repeating notifications for blood pressure measurement times.
    /// - Parameters:
    ///   - times: Array of DateComponents representing local times to trigger each day/week as applicable.
    ///   - replaceExisting: If true, existing BP notifications should be replaced by the new schedule.
    func scheduleBloodPressureNotifications(at times: [DateComponents], replaceExisting: Bool) async throws

    /// Schedules repeating notifications for glucose measurement slots.
    /// - Parameters:
    ///   - schedule: Mapping of glucose slots to arrays of DateComponents for each slot.
    ///   - replaceExisting: If true, existing glucose notifications should be replaced by the new schedule.
    func scheduleGlucoseNotifications(_ schedule: [GlucoseSlot: [DateComponents]], replaceExisting: Bool) async throws

    // MARK: Cancel / Reschedule
    /// Cancels all scheduled notifications (both blood pressure and glucose).
    func cancelAllScheduledNotifications() async throws

    /// Cancels only blood pressure notifications.
    func cancelBloodPressureNotifications() async throws

    /// Cancels glucose notifications for the specified slots. If `slots` is nil, cancels all glucose notifications.
    func cancelGlucoseNotifications(slots: Set<GlucoseSlot>?) async throws

    /// Replaces the existing blood pressure notification schedule with the provided times.
    func rescheduleBloodPressureNotifications(at times: [DateComponents]) async throws

    /// Replaces the existing glucose notification schedule with the provided slot mapping.
    func rescheduleGlucoseNotifications(_ schedule: [GlucoseSlot: [DateComponents]]) async throws

    // MARK: User Actions
    /// Snoozes a delivered notification by the given number of minutes.
    func snoozeNotification(with identifier: String, by minutes: Int) async throws

    /// Skips a delivered notification (e.g., user indicates they'll skip this reminder).
    func skipNotification(with identifier: String) async throws

    /// Moves a delivered notification to a new fire date.
    func moveNotification(with identifier: String, to date: Date) async throws
}

// MARK: - AnalyticsRepository

/// Abstraction over analytics logging.
public protocol AnalyticsRepository {
    /// Logs when the app is opened/foregrounded.
    func logAppOpen() async

    /// Logs when a measurement is recorded by the user.
    func logMeasurementLogged(type: MeasurementType) async

    /// Logs when a schedule (BP or glucose) is updated.
    func logScheduleUpdated(for type: MeasurementType) async

    /// Logs when the user exports data as CSV.
    func logExportCSV() async

    /// Logs a successful Google sync operation.
    /// - Parameter count: Optional number of items synced.
    func logGoogleSyncSuccess(count: Int?) async

    /// Logs a failed Google sync operation.
    /// - Parameter errorDescription: Optional error details for diagnostics.
    func logGoogleSyncFailure(errorDescription: String?) async

    /// Logs when Google integration is enabled.
    func logGoogleEnabled() async

    /// Logs when Google integration is disabled.
    func logGoogleDisabled() async
}
