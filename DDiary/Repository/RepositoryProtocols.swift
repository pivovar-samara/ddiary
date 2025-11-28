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
/// Abstraction for CRUD and query operations over blood pressure and glucose measurements using DTOs.
public protocol MeasurementsRepository {
    // MARK: BPMeasurement CRUD
    func createBPMeasurement(_ measurement: BPMeasurementDTO) async throws -> BPMeasurementDTO
    func getBPMeasurement(id: UUID) async throws -> BPMeasurementDTO?
    func updateBPMeasurement(_ measurement: BPMeasurementDTO) async throws -> BPMeasurementDTO
    func deleteBPMeasurement(id: UUID) async throws

    // MARK: GlucoseMeasurement CRUD
    func createGlucoseMeasurement(_ measurement: GlucoseMeasurementDTO) async throws -> GlucoseMeasurementDTO
    func getGlucoseMeasurement(id: UUID) async throws -> GlucoseMeasurementDTO?
    func updateGlucoseMeasurement(_ measurement: GlucoseMeasurementDTO) async throws -> GlucoseMeasurementDTO
    func deleteGlucoseMeasurement(id: UUID) async throws

    // MARK: Queries by type
    func fetchAllBloodPressureMeasurements() async throws -> [BPMeasurementDTO]
    func fetchAllGlucoseMeasurements() async throws -> [GlucoseMeasurementDTO]

    // MARK: Queries by date range
    func fetchBloodPressureMeasurements(from startDate: Date, to endDate: Date) async throws -> [BPMeasurementDTO]
    func fetchGlucoseMeasurements(from startDate: Date, to endDate: Date) async throws -> [GlucoseMeasurementDTO]
}

// MARK: - RotationScheduleRepository
@MainActor
public protocol RotationScheduleRepository {
    func getRotationState() async throws -> GlucoseRotationStateDTO
    func updateRotationState(_ state: GlucoseRotationStateDTO) async throws -> GlucoseRotationStateDTO
}

// MARK: - SettingsRepository
@MainActor
/// Abstraction over user settings persistence using DTOs.
public protocol SettingsRepository {
    func getOrCreateUserSettings() async throws -> UserSettingsDTO
    func updateUserSettings(_ settings: UserSettingsDTO) async throws -> UserSettingsDTO
}

// MARK: - GoogleIntegrationRepository
@MainActor
/// Abstraction over Google integration persistence and token lifecycle.
public protocol GoogleIntegrationRepository {
    func getOrCreateGoogleIntegration() async throws -> GoogleIntegration
    func updateGoogleIntegration(_ integration: GoogleIntegration) async throws -> GoogleIntegration
    func clearTokensOnLogout() async throws
}

// MARK: - NotificationsRepository
/// Abstraction over local notification scheduling and user actions.
public protocol NotificationsRepository {
    func requestAuthorization() async throws -> Bool
    func scheduleBloodPressureNotifications(at times: [DateComponents], replaceExisting: Bool) async throws
    func scheduleGlucoseNotifications(_ schedule: [GlucoseSlot: [DateComponents]], replaceExisting: Bool) async throws
    func cancelAllScheduledNotifications() async throws
    func cancelBloodPressureNotifications() async throws
    func cancelGlucoseNotifications(slots: Set<GlucoseSlot>?) async throws
    func rescheduleBloodPressureNotifications(at times: [DateComponents]) async throws
    func rescheduleGlucoseNotifications(_ schedule: [GlucoseSlot: [DateComponents]]) async throws
    func snoozeNotification(with identifier: String, by minutes: Int) async throws
    func skipNotification(with identifier: String) async throws
    func moveNotification(with identifier: String, to date: Date) async throws
}

// MARK: - AnalyticsRepository
/// Abstraction over analytics logging.
public protocol AnalyticsRepository {
    func logAppOpen() async
    func logMeasurementLogged(type: MeasurementType) async
    func logScheduleUpdated(for type: MeasurementType) async
    func logExportCSV() async
    func logGoogleSyncSuccess(count: Int?) async
    func logGoogleSyncFailure(errorDescription: String?) async
    func logGoogleEnabled() async
    func logGoogleDisabled() async
}
