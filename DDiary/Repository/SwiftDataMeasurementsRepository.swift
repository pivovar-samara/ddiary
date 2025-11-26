//
//  SwiftDataMeasurementsRepository.swift
//  DDiary
//
//  Created by Assistant on 26.11.25.
//

import Foundation
import SwiftData

@MainActor
public final class SwiftDataMeasurementsRepository: MeasurementsRepository {
    private let context: ModelContext

    public init(modelContext: ModelContext) {
        self.context = modelContext
    }

    // MARK: - BP CRUD
    public func createBPMeasurement(_ measurement: BPMeasurement) async throws -> BPMeasurement {
        context.insert(measurement)
        try context.save()
        return measurement
    }

    public func getBPMeasurement(id: UUID) async throws -> BPMeasurement? {
        var descriptor = FetchDescriptor<BPMeasurement>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        let results = try context.fetch(descriptor)
        return results.first
    }

    public func updateBPMeasurement(_ measurement: BPMeasurement) async throws -> BPMeasurement {
        // Find existing and update fields, or insert if missing
        if let existing = try await getBPMeasurement(id: measurement.id) {
            existing.timestamp = measurement.timestamp
            existing.systolic = measurement.systolic
            existing.diastolic = measurement.diastolic
            existing.pulse = measurement.pulse
            existing.comment = measurement.comment
            existing.googleSyncStatus = measurement.googleSyncStatus
            existing.googleLastError = measurement.googleLastError
            existing.googleLastSyncAt = measurement.googleLastSyncAt
            try context.save()
            return existing
        } else {
            context.insert(measurement)
            try context.save()
            return measurement
        }
    }

    public func deleteBPMeasurement(id: UUID) async throws {
        if let existing = try await getBPMeasurement(id: id) {
            context.delete(existing)
            try context.save()
        }
    }

    // MARK: - Glucose CRUD
    public func createGlucoseMeasurement(_ measurement: GlucoseMeasurement) async throws -> GlucoseMeasurement {
        context.insert(measurement)
        try context.save()
        return measurement
    }

    public func getGlucoseMeasurement(id: UUID) async throws -> GlucoseMeasurement? {
        var descriptor = FetchDescriptor<GlucoseMeasurement>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        let results = try context.fetch(descriptor)
        return results.first
    }

    public func updateGlucoseMeasurement(_ measurement: GlucoseMeasurement) async throws -> GlucoseMeasurement {
        if let existing = try await getGlucoseMeasurement(id: measurement.id) {
            existing.timestamp = measurement.timestamp
            existing.value = measurement.value
            existing.unit = measurement.unit
            existing.measurementType = measurement.measurementType
            existing.mealSlot = measurement.mealSlot
            existing.comment = measurement.comment
            existing.googleSyncStatus = measurement.googleSyncStatus
            existing.googleLastError = measurement.googleLastError
            existing.googleLastSyncAt = measurement.googleLastSyncAt
            try context.save()
            return existing
        } else {
            context.insert(measurement)
            try context.save()
            return measurement
        }
    }

    public func deleteGlucoseMeasurement(id: UUID) async throws {
        if let existing = try await getGlucoseMeasurement(id: id) {
            context.delete(existing)
            try context.save()
        }
    }

    // MARK: - Queries (All)
    public func fetchAllBloodPressureMeasurements() async throws -> [BPMeasurement] {
        let descriptor = FetchDescriptor<BPMeasurement>(
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        return try context.fetch(descriptor)
    }

    public func fetchAllGlucoseMeasurements() async throws -> [GlucoseMeasurement] {
        let descriptor = FetchDescriptor<GlucoseMeasurement>(
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        return try context.fetch(descriptor)
    }

    // MARK: - Queries (Date Range)
    public func fetchBloodPressureMeasurements(from startDate: Date, to endDate: Date) async throws -> [BPMeasurement] {
        let descriptor = FetchDescriptor<BPMeasurement>(
            predicate: #Predicate { $0.timestamp >= startDate && $0.timestamp <= endDate },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        return try context.fetch(descriptor)
    }

    public func fetchGlucoseMeasurements(from startDate: Date, to endDate: Date) async throws -> [GlucoseMeasurement] {
        let descriptor = FetchDescriptor<GlucoseMeasurement>(
            predicate: #Predicate { $0.timestamp >= startDate && $0.timestamp <= endDate },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        return try context.fetch(descriptor)
    }

    // MARK: - Google Sync Filters
    public func fetchBloodPressureMeasurementsNeedingGoogleSync() async throws -> [BPMeasurement] {
        let notSynced = GoogleSyncStatus.notSynced.rawValue
        let queued = GoogleSyncStatus.queued.rawValue
        let failed = GoogleSyncStatus.failed.rawValue
        let descriptor = FetchDescriptor<BPMeasurement>(
            predicate: #Predicate {
                ($0.googleSyncStatusRaw == notSynced) ||
                ($0.googleSyncStatusRaw == queued) ||
                ($0.googleSyncStatusRaw == failed)
            },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        return try context.fetch(descriptor)
    }

    public func fetchGlucoseMeasurementsNeedingGoogleSync() async throws -> [GlucoseMeasurement] {
        let notSynced = GoogleSyncStatus.notSynced.rawValue
        let queued = GoogleSyncStatus.queued.rawValue
        let failed = GoogleSyncStatus.failed.rawValue
        let descriptor = FetchDescriptor<GlucoseMeasurement>(
            predicate: #Predicate {
                ($0.googleSyncStatusRaw == notSynced) ||
                ($0.googleSyncStatusRaw == queued) ||
                ($0.googleSyncStatusRaw == failed)
            },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        return try context.fetch(descriptor)
    }
}

