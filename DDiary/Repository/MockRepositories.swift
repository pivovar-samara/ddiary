//
//  MockRepositories.swift
//  DDiaryTestsSupport
//
//  Created by Assistant on 26.11.25.
//

import Foundation

#if DEBUG

// MARK: - Mock Measurements Repository (actor-backed, in-memory)
@MainActor public final class MockMeasurementsRepository: MeasurementsRepository {
    private var bpMeasurements: [UUID: BPMeasurement] = [:]
    private var glucoseMeasurements: [UUID: GlucoseMeasurement] = [:]

    public init() {}

    // MARK: BP CRUD
    public func createBPMeasurement(_ measurement: BPMeasurement) async throws -> BPMeasurement {
        bpMeasurements[measurement.id] = measurement
        return measurement
    }

    public func getBPMeasurement(id: UUID) async throws -> BPMeasurement? {
        return bpMeasurements[id]
    }

    public func updateBPMeasurement(_ measurement: BPMeasurement) async throws -> BPMeasurement {
        bpMeasurements[measurement.id] = measurement
        return measurement
    }

    public func deleteBPMeasurement(id: UUID) async throws {
        bpMeasurements.removeValue(forKey: id)
    }

    // MARK: Glucose CRUD
    public func createGlucoseMeasurement(_ measurement: GlucoseMeasurement) async throws -> GlucoseMeasurement {
        glucoseMeasurements[measurement.id] = measurement
        return measurement
    }

    public func getGlucoseMeasurement(id: UUID) async throws -> GlucoseMeasurement? {
        return glucoseMeasurements[id]
    }

    public func updateGlucoseMeasurement(_ measurement: GlucoseMeasurement) async throws -> GlucoseMeasurement {
        glucoseMeasurements[measurement.id] = measurement
        return measurement
    }

    public func deleteGlucoseMeasurement(id: UUID) async throws {
        glucoseMeasurements.removeValue(forKey: id)
    }

    // MARK: Queries
    public func fetchAllBloodPressureMeasurements() async throws -> [BPMeasurement] {
        return bpMeasurements.values.sorted { $0.timestamp < $1.timestamp }
    }

    public func fetchAllGlucoseMeasurements() async throws -> [GlucoseMeasurement] {
        return glucoseMeasurements.values.sorted { $0.timestamp < $1.timestamp }
    }

    public func fetchBloodPressureMeasurements(from startDate: Date, to endDate: Date) async throws -> [BPMeasurement] {
        return bpMeasurements.values
            .filter { $0.timestamp >= startDate && $0.timestamp <= endDate }
            .sorted { $0.timestamp < $1.timestamp }
    }

    public func fetchGlucoseMeasurements(from startDate: Date, to endDate: Date) async throws -> [GlucoseMeasurement] {
        return glucoseMeasurements.values
            .filter { $0.timestamp >= startDate && $0.timestamp <= endDate }
            .sorted { $0.timestamp < $1.timestamp }
    }

    public func fetchBloodPressureMeasurementsNeedingGoogleSync() async throws -> [BPMeasurement] {
        return bpMeasurements.values
            .filter { $0.googleSyncStatus == .notSynced || $0.googleSyncStatus == .queued || $0.googleSyncStatus == .failed }
            .sorted { $0.timestamp < $1.timestamp }
    }

    public func fetchGlucoseMeasurementsNeedingGoogleSync() async throws -> [GlucoseMeasurement] {
        return glucoseMeasurements.values
            .filter { $0.googleSyncStatus == .notSynced || $0.googleSyncStatus == .queued || $0.googleSyncStatus == .failed }
            .sorted { $0.timestamp < $1.timestamp }
    }
}

// MARK: - Mock Settings Repository
@MainActor public final class MockSettingsRepository: SettingsRepository {
    private var settings: UserSettings?
    public init(initial: UserSettings? = nil) { self.settings = initial }

    public func getOrCreateUserSettings() async throws -> UserSettings {
        if let s = settings { return s }
        let created = UserSettings.default()
        settings = created
        return created
    }

    public func updateUserSettings(_ settings: UserSettings) async throws -> UserSettings {
        self.settings = settings
        return settings
    }
}

// MARK: - Mock Google Integration Repository
@MainActor public final class MockGoogleIntegrationRepository: GoogleIntegrationRepository {
    private var integration: GoogleIntegration?
    public init(initial: GoogleIntegration? = nil) { self.integration = initial }

    public func getOrCreateGoogleIntegration() async throws -> GoogleIntegration {
        if let i = integration { return i }
        let created = GoogleIntegration()
        integration = created
        return created
    }

    public func updateGoogleIntegration(_ integration: GoogleIntegration) async throws -> GoogleIntegration {
        self.integration = integration
        return integration
    }

    public func clearTokensOnLogout() async throws {
        guard let i = integration else { return }
        i.refreshToken = nil
        i.googleUserId = nil
        i.isEnabled = false
    }
}

#endif
