import Foundation
import SwiftData

@MainActor
final class SwiftDataMeasurementsRepository: MeasurementsRepository {
    private let context: ModelContext

    // MARK: - Initializers
    init(modelContainer: ModelContainer) {
        self.context = ModelContext(modelContainer)
    }

    init(modelContext: ModelContext) {
        self.context = modelContext
    }

    // MARK: - BP CRUD
    func insertBP(_ measurement: BPMeasurement) async throws {
        context.insert(measurement)
        try context.save()
    }

    func updateBP(_ measurement: BPMeasurement) async throws {
        // SwiftData tracks changes on managed instances automatically.
        try context.save()
    }

    func deleteBP(_ measurement: BPMeasurement) async throws {
        context.delete(measurement)
        try context.save()
    }

    func bpMeasurement(id: UUID) async throws -> BPMeasurement? {
        let descriptor = FetchDescriptor<BPMeasurement>(
            predicate: #Predicate { $0.id == id }
        )
        return try context.fetch(descriptor).first
    }

    func bpMeasurements(from: Date, to: Date) async throws -> [BPMeasurement] {
        let predicate = #Predicate<BPMeasurement> { m in
            m.timestamp >= from && m.timestamp <= to
        }
        let sort = [SortDescriptor(\BPMeasurement.timestamp, order: .forward)]
        let descriptor = FetchDescriptor<BPMeasurement>(predicate: predicate, sortBy: sort)
        return try context.fetch(descriptor)
    }

    func pendingOrFailedBPSync() async throws -> [BPMeasurement] {
        let statusValuePending = GoogleSyncStatus.pending
        let statusValueFailed = GoogleSyncStatus.failed
        let predicate = #Predicate<BPMeasurement> { m in
            m.googleSyncStatus == statusValuePending || m.googleSyncStatus == statusValueFailed
        }
        let sort = [SortDescriptor(\BPMeasurement.timestamp, order: .forward)]
        let descriptor = FetchDescriptor<BPMeasurement>(predicate: predicate, sortBy: sort)
        return try context.fetch(descriptor)
    }

    // MARK: - Glucose CRUD
    func insertGlucose(_ measurement: GlucoseMeasurement) async throws {
        context.insert(measurement)
        try context.save()
    }

    func updateGlucose(_ measurement: GlucoseMeasurement) async throws {
        // SwiftData tracks changes on managed instances automatically.
        try context.save()
    }

    func deleteGlucose(_ measurement: GlucoseMeasurement) async throws {
        context.delete(measurement)
        try context.save()
    }

    func glucoseMeasurement(id: UUID) async throws -> GlucoseMeasurement? {
        let descriptor = FetchDescriptor<GlucoseMeasurement>(
            predicate: #Predicate { $0.id == id }
        )
        return try context.fetch(descriptor).first
    }

    func glucoseMeasurements(from: Date, to: Date) async throws -> [GlucoseMeasurement] {
        let predicate = #Predicate<GlucoseMeasurement> { m in
            m.timestamp >= from && m.timestamp <= to
        }
        let sort = [SortDescriptor(\GlucoseMeasurement.timestamp, order: .forward)]
        let descriptor = FetchDescriptor<GlucoseMeasurement>(predicate: predicate, sortBy: sort)
        return try context.fetch(descriptor)
    }

    func pendingOrFailedGlucoseSync() async throws -> [GlucoseMeasurement] {
        let statusValuePending = GoogleSyncStatus.pending
        let statusValueFailed = GoogleSyncStatus.failed
        let predicate = #Predicate<GlucoseMeasurement> { m in
            m.googleSyncStatus == statusValuePending || m.googleSyncStatus == statusValueFailed
        }
        let sort = [SortDescriptor(\GlucoseMeasurement.timestamp, order: .forward)]
        let descriptor = FetchDescriptor<GlucoseMeasurement>(predicate: predicate, sortBy: sort)
        return try context.fetch(descriptor)
    }
}

