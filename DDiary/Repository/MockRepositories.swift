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
        integration.refreshToken = nil
        integration.spreadsheetId = nil
        integration.googleUserId = nil
        integration.isEnabled = false
        self.integration = integration
    }
}
