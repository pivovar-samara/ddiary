import Foundation
import SwiftData

@MainActor
public final class SwiftDataRotationScheduleRepository: RotationScheduleRepository {
    private let context: ModelContext

    public init(modelContext: ModelContext) {
        self.context = modelContext
    }

    public func getRotationState() async throws -> GlucoseRotationStateDTO {
        let descriptor = FetchDescriptor<GlucoseRotationConfigModel>(fetchLimit: 1)
        if let existing = try context.fetch(descriptor).first {
            return GlucoseRotationStateDTO(model: existing)
        } else {
            let model = GlucoseRotationConfigModel()
            context.insert(model)
            try context.save()
            return GlucoseRotationStateDTO(model: model)
        }
    }

    public func updateRotationState(_ state: GlucoseRotationStateDTO) async throws -> GlucoseRotationStateDTO {
        if let existing = try await lookupModel(id: state.id) {
            state.applying(to: existing)
            try context.save()
            return GlucoseRotationStateDTO(model: existing)
        } else {
            let model = state.makeModel()
            context.insert(model)
            try context.save()
            return GlucoseRotationStateDTO(model: model)
        }
    }

    private func lookupModel(id: UUID) async throws -> GlucoseRotationConfigModel? {
        var descriptor = FetchDescriptor<GlucoseRotationConfigModel>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
