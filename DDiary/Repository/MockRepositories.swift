import Foundation

// MARK: - Mock Measurements Repository

@MainActor
final class MockMeasurementsRepository: MeasurementsRepository {
    private var bp: [UUID: BPMeasurement] = [:]
    private var glucose: [UUID: GlucoseMeasurement] = [:]

    // MARK: BP
    func insertBP(_ measurement: BPMeasurement) async throws {
        bp[measurement.id] = measurement
    }

    func updateBP(_ measurement: BPMeasurement) async throws {
        bp[measurement.id] = measurement
    }

    func deleteBP(_ measurement: BPMeasurement) async throws {
        bp.removeValue(forKey: measurement.id)
    }

    func bpMeasurement(id: UUID) async throws -> BPMeasurement? {
        bp[id]
    }

    func bpMeasurements(from: Date, to: Date) async throws -> [BPMeasurement] {
        bp.values.filter { $0.timestamp >= from && $0.timestamp <= to }.sorted { $0.timestamp < $1.timestamp }
    }

    func pendingOrFailedBPSync() async throws -> [BPMeasurement] {
        bp.values.filter { $0.googleSyncStatus == .pending || $0.googleSyncStatus == .failed }.sorted { $0.timestamp < $1.timestamp }
    }

    // MARK: Glucose
    func insertGlucose(_ measurement: GlucoseMeasurement) async throws {
        glucose[measurement.id] = measurement
    }

    func updateGlucose(_ measurement: GlucoseMeasurement) async throws {
        glucose[measurement.id] = measurement
    }

    func deleteGlucose(_ measurement: GlucoseMeasurement) async throws {
        glucose.removeValue(forKey: measurement.id)
    }

    func glucoseMeasurement(id: UUID) async throws -> GlucoseMeasurement? {
        glucose[id]
    }

    func glucoseMeasurements(from: Date, to: Date) async throws -> [GlucoseMeasurement] {
        glucose.values.filter { $0.timestamp >= from && $0.timestamp <= to }.sorted { $0.timestamp < $1.timestamp }
    }

    func pendingOrFailedGlucoseSync() async throws -> [GlucoseMeasurement] {
        glucose.values.filter { $0.googleSyncStatus == .pending || $0.googleSyncStatus == .failed }.sorted { $0.timestamp < $1.timestamp }
    }
}

// MARK: - Mock Settings Repository

@MainActor
final class MockSettingsRepository: SettingsRepository {
    private var settings: UserSettings?

    func getOrCreate() async throws -> UserSettings {
        if let s = settings { return s }
        let s = UserSettings.default()
        settings = s
        return s
    }

    func save(_ settings: UserSettings) async throws {
        self.settings = settings
    }

    func update(_ settings: UserSettings) async throws {
        self.settings = settings
    }
}

// MARK: - Mock Google Integration Repository

@MainActor
final class MockGoogleIntegrationRepository: GoogleIntegrationRepository {
    private var integration: GoogleIntegration? = nil
    private var refreshToken: String? = nil

    func getOrCreate() async throws -> GoogleIntegration {
        if let i = integration { return i }
        let i = GoogleIntegration()
        integration = i
        return i
    }

    func save(_ integration: GoogleIntegration) async throws {
        self.integration = integration
    }

    func update(_ integration: GoogleIntegration) async throws {
        self.integration = integration
    }

    func clearTokens(_ integration: GoogleIntegration) async throws {
        integration.spreadsheetId = nil
        integration.googleUserId = nil
        integration.isEnabled = false
        self.integration = integration
        refreshToken = nil
    }

    func getRefreshToken() async throws -> String? {
        refreshToken
    }

    func setRefreshToken(_ token: String?) async throws {
        refreshToken = token
    }
}

// MARK: - Demo Infrastructure

@MainActor
final class InMemoryTokenStorage: TokenStorage {
    private var store: [String: String] = [:]

    func read(key: String) -> String? {
        store[key]
    }

    func write(_ token: String, key: String) throws {
        store[key] = token
    }

    func delete(key: String) throws {
        store.removeValue(forKey: key)
    }
}

struct SilentNotificationsRepository: NotificationsRepository, Sendable {
    func requestAuthorization() async throws -> Bool { false }
    func hasPendingNotificationRequests() async -> Bool { false }
    func scheduleBloodPressure(times _: [Int], activeWeekdays _: Set<Int>) async throws {}
    func cancelBloodPressure() async {}
    func rescheduleBloodPressure(times _: [Int], activeWeekdays _: Set<Int>) async throws {}
    func scheduleGlucoseBeforeMeal(
        breakfast _: DateComponents,
        lunch _: DateComponents,
        dinner _: DateComponents,
        isEnabled _: Bool
    ) async throws {}
    func scheduleGlucoseAfterMeal2h(
        breakfast _: DateComponents,
        lunch _: DateComponents,
        dinner _: DateComponents,
        isEnabled _: Bool
    ) async throws {}
    func scheduleGlucoseBedtime(isEnabled _: Bool, time _: DateComponents?) async throws {}
    func cancelGlucose() async {}
    func rescheduleGlucose(
        breakfast _: DateComponents,
        lunch _: DateComponents,
        dinner _: DateComponents,
        enableBeforeMeal _: Bool,
        enableAfterMeal2h _: Bool,
        bedtimeTime _: DateComponents?
    ) async throws {}
    func rescheduleGlucoseCycle(
        configuration _: GlucoseCycleConfiguration,
        startDate _: Date,
        numberOfDays _: Int
    ) async throws {}
    func scheduleOneOff(
        at _: Date,
        identifier _: String,
        title _: String,
        body _: String,
        categoryIdentifier _: String,
        userInfo _: [AnyHashable: Any]
    ) async {}
    func snooze(
        originalIdentifier _: String,
        minutes _: Int,
        title _: String,
        body _: String,
        categoryIdentifier _: String,
        mealSlotRawValue _: String?,
        measurementTypeRawValue _: String?
    ) async {}
    func cancel(withIdentifier _: String) async {}
    func cancelPlannedBloodPressureNotification(at _: Date) async {}
    func cancelPlannedGlucoseNotification(measurementType _: GlucoseMeasurementType, at _: Date) async {}
    func scheduledReminders(on _: Date) async -> [ScheduledReminder] { [] }
    func cancelAll() async {}
    func cancelAllExceptOneOffRequests() async {}
}

struct NoopAnalyticsRepository: AnalyticsRepository, Sendable {
    func logAppOpen() async {}
    func logMeasurementLogged(kind _: AnalyticsMeasurementKind) async {}
    func logMeasurementSaveFailed(kind _: AnalyticsMeasurementKind, reason _: String?) async {}
    func logScheduleUpdated(kind _: AnalyticsScheduleKind) async {}
    func logScheduleUpdateFailed(kind _: AnalyticsScheduleKind, reason _: String?) async {}
    func logExportCSV() async {}
    func logGoogleSyncSuccess() async {}
    func logGoogleSyncFailure(reason _: String?) async {}
    func logGoogleSyncFinished(successCount _: Int, failureCount _: Int) async {}
    func logGoogleEnabled() async {}
    func logGoogleDisabled() async {}
}

struct DisabledGoogleSheetsClient: GoogleSheetsClient, Sendable {
    func appendBloodPressureRow(_ row: GoogleSheetsBPRow, credentials _: GoogleSheetsCredentials) async throws {
        _ = row
    }

    func appendGlucoseRow(_ row: GoogleSheetsGlucoseRow, credentials _: GoogleSheetsCredentials) async throws {
        _ = row
    }
}
