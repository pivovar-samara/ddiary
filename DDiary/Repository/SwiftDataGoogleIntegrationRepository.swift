import Foundation
import SwiftData

@MainActor
final class SwiftDataGoogleIntegrationRepository: GoogleIntegrationRepository {
    private let context: ModelContext

    // MARK: - Initializers
    init(modelContainer: ModelContainer) {
        self.context = ModelContext(modelContainer)
    }

    init(modelContext: ModelContext) {
        self.context = modelContext
    }

    // MARK: - Google Integration
    func getOrCreate() async throws -> GoogleIntegration {
        let descriptor = FetchDescriptor<GoogleIntegration>()
        if let existing = try context.fetch(descriptor).first {
            return existing
        }
        let integration = GoogleIntegration()
        context.insert(integration)
        try context.save()
        return integration
    }

    func save(_ integration: GoogleIntegration) async throws {
        let integrationID = integration.id
        let descriptor = FetchDescriptor<GoogleIntegration>(
            predicate: #Predicate { $0.id == integrationID }
        )
        let exists = try context.fetch(descriptor).first != nil
        if !exists {
            context.insert(integration)
        }
        try context.save()
    }

    func update(_ integration: GoogleIntegration) async throws {
        try context.save()
    }

    func clearTokens(_ integration: GoogleIntegration) async throws {
        integration.refreshToken = nil
        integration.spreadsheetId = nil
        integration.googleUserId = nil
        integration.isEnabled = false
        try context.save()
    }
}
