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
    public func createBPMeasurement(_ measurement: BPMeasurementDTO) async throws -> BPMeasurementDTO {
        let model = measurement.makeModel()
        context.insert(model)
        try context.save()
        return BPMeasurementDTO(model: model)
    }

    public func getBPMeasurement(id: UUID) async throws -> BPMeasurementDTO? {
        var descriptor = FetchDescriptor<BPMeasurementModel>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        let results = try context.fetch(descriptor)
        return results.first.map(BPMeasurementDTO.init(model:))
    }

    public func updateBPMeasurement(_ measurement: BPMeasurementDTO) async throws -> BPMeasurementDTO {
        if let existing = try await getBPMeasurementModel(id: measurement.id) {
            measurement.applying(to: existing)
            try context.save()
            return BPMeasurementDTO(model: existing)
        } else {
            return try createBPMeasurement(measurement)
        }
    }

    public func deleteBPMeasurement(id: UUID) async throws {
        if let existing = try await getBPMeasurementModel(id: id) {
            context.delete(existing)
            try context.save()
        }
    }

    // MARK: - Glucose CRUD
    public func createGlucoseMeasurement(_ measurement: GlucoseMeasurementDTO) async throws -> GlucoseMeasurementDTO {
        let model = measurement.makeModel()
        context.insert(model)
        try context.save()
        return GlucoseMeasurementDTO(model: model)
    }

    public func getGlucoseMeasurement(id: UUID) async throws -> GlucoseMeasurementDTO? {
        var descriptor = FetchDescriptor<GlucoseMeasurementModel>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        let results = try context.fetch(descriptor)
        return results.first.map(GlucoseMeasurementDTO.init(model:))
    }

    public func updateGlucoseMeasurement(_ measurement: GlucoseMeasurementDTO) async throws -> GlucoseMeasurementDTO {
        if let existing = try await getGlucoseMeasurementModel(id: measurement.id) {
            measurement.applying(to: existing)
            try context.save()
            return GlucoseMeasurementDTO(model: existing)
        } else {
            return try createGlucoseMeasurement(measurement)
        }
    }

    public func deleteGlucoseMeasurement(id: UUID) async throws {
        if let existing = try await getGlucoseMeasurementModel(id: id) {
            context.delete(existing)
            try context.save()
        }
    }

    // MARK: - Queries (All)
    public func fetchAllBloodPressureMeasurements() async throws -> [BPMeasurementDTO] {
        let descriptor = FetchDescriptor<BPMeasurementModel>(
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        let results = try context.fetch(descriptor)
        return results.map(BPMeasurementDTO.init(model:))
    }

    public func fetchAllGlucoseMeasurements() async throws -> [GlucoseMeasurementDTO] {
        let descriptor = FetchDescriptor<GlucoseMeasurementModel>(
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        let results = try context.fetch(descriptor)
        return results.map(GlucoseMeasurementDTO.init(model:))
    }

    // MARK: - Queries (Date Range)
    public func fetchBloodPressureMeasurements(from startDate: Date, to endDate: Date) async throws -> [BPMeasurementDTO] {
        let descriptor = FetchDescriptor<BPMeasurementModel>(
            predicate: #Predicate { $0.timestamp >= startDate && $0.timestamp <= endDate },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        let results = try context.fetch(descriptor)
        return results.map(BPMeasurementDTO.init(model:))
    }

    public func fetchGlucoseMeasurements(from startDate: Date, to endDate: Date) async throws -> [GlucoseMeasurementDTO] {
        let descriptor = FetchDescriptor<GlucoseMeasurementModel>(
            predicate: #Predicate { $0.timestamp >= startDate && $0.timestamp <= endDate },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        let results = try context.fetch(descriptor)
        return results.map(GlucoseMeasurementDTO.init(model:))
    }

    // MARK: - Helpers
    private func getBPMeasurementModel(id: UUID) async throws -> BPMeasurementModel? {
        var descriptor = FetchDescriptor<BPMeasurementModel>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func getGlucoseMeasurementModel(id: UUID) async throws -> GlucoseMeasurementModel? {
        var descriptor = FetchDescriptor<GlucoseMeasurementModel>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
