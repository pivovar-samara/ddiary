import Foundation
import SwiftData

@MainActor
final class SwiftDataSettingsRepository: SettingsRepository {
    private let context: ModelContext

    // MARK: - Initializers
    init(modelContainer: ModelContainer) {
        self.context = ModelContext(modelContainer)
    }

    init(modelContext: ModelContext) {
        self.context = modelContext
    }

    // MARK: - Settings
    func getOrCreate() async throws -> UserSettings {
        let descriptor = FetchDescriptor<UserSettings>()
        if let existing = try context.fetch(descriptor).first {
            return existing
        }
        let settings = UserSettings.default()
        context.insert(settings)
        try context.save()
        return settings
    }

    func save(_ settings: UserSettings) async throws {
        let settingsID = settings.id
        let descriptor = FetchDescriptor<UserSettings>(
            predicate: #Predicate { $0.id == settingsID }
        )
        let exists = try context.fetch(descriptor).first != nil
        if !exists {
            context.insert(settings)
        }
        try context.save()
    }

    func update(_ settings: UserSettings) async throws {
        // SwiftData tracks changes automatically on managed instances.
        try context.save()
    }
}
