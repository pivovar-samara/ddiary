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
    private var bpMeasurements: [UUID: BPMeasurementDTO] = [:]
    private var glucoseMeasurements: [UUID: GlucoseMeasurementDTO] = [:]

    public init() {}

    // MARK: BP CRUD
    public func createBPMeasurement(_ measurement: BPMeasurementDTO) async throws -> BPMeasurementDTO {
        bpMeasurements[measurement.id] = measurement
        return measurement
    }

    public func getBPMeasurement(id: UUID) async throws -> BPMeasurementDTO? {
        return bpMeasurements[id]
    }

    public func updateBPMeasurement(_ measurement: BPMeasurementDTO) async throws -> BPMeasurementDTO {
        bpMeasurements[measurement.id] = measurement
        return measurement
    }

    public func deleteBPMeasurement(id: UUID) async throws {
        bpMeasurements.removeValue(forKey: id)
    }

    // MARK: Glucose CRUD
    public func createGlucoseMeasurement(_ measurement: GlucoseMeasurementDTO) async throws -> GlucoseMeasurementDTO {
        glucoseMeasurements[measurement.id] = measurement
        return measurement
    }

    public func getGlucoseMeasurement(id: UUID) async throws -> GlucoseMeasurementDTO? {
        return glucoseMeasurements[id]
    }

    public func updateGlucoseMeasurement(_ measurement: GlucoseMeasurementDTO) async throws -> GlucoseMeasurementDTO {
        glucoseMeasurements[measurement.id] = measurement
        return measurement
    }

    public func deleteGlucoseMeasurement(id: UUID) async throws {
        glucoseMeasurements.removeValue(forKey: id)
    }

    // MARK: Queries
    public func fetchAllBloodPressureMeasurements() async throws -> [BPMeasurementDTO] {
        return bpMeasurements.values.sorted { $0.timestamp < $1.timestamp }
    }

    public func fetchAllGlucoseMeasurements() async throws -> [GlucoseMeasurementDTO] {
        return glucoseMeasurements.values.sorted { $0.timestamp < $1.timestamp }
    }

    public func fetchBloodPressureMeasurements(from startDate: Date, to endDate: Date) async throws -> [BPMeasurementDTO] {
        return bpMeasurements.values
            .filter { $0.timestamp >= startDate && $0.timestamp <= endDate }
            .sorted { $0.timestamp < $1.timestamp }
    }

    public func fetchGlucoseMeasurements(from startDate: Date, to endDate: Date) async throws -> [GlucoseMeasurementDTO] {
        return glucoseMeasurements.values
            .filter { $0.timestamp >= startDate && $0.timestamp <= endDate }
            .sorted { $0.timestamp < $1.timestamp }
    }
}

// MARK: - Mock Settings Repository
@MainActor public final class MockSettingsRepository: SettingsRepository {
    private var settings: UserSettingsDTO?
    public init(initial: UserSettingsDTO? = nil) { self.settings = initial }

    public func getOrCreateUserSettings() async throws -> UserSettingsDTO {
        if let s = settings { return s }
        let created = UserSettingsDTO()
        settings = created
        return created
    }

    public func updateUserSettings(_ settings: UserSettingsDTO) async throws -> UserSettingsDTO {
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
