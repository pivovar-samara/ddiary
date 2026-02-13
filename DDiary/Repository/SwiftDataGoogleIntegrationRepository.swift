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
        let all = try context.fetch(descriptor)
        guard !all.isEmpty else {
            let integration = GoogleIntegration()
            context.insert(integration)
            try context.save()
            return integration
        }

        guard all.count > 1 else {
            return all[0]
        }

        let primary = selectPrimaryIntegration(from: all)
        mergeMissingValues(into: primary, from: all.filter { $0.id != primary.id })

        for duplicate in all where duplicate.id != primary.id {
            context.delete(duplicate)
        }

        try context.save()
        return primary
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

private extension SwiftDataGoogleIntegrationRepository {
    func selectPrimaryIntegration(from integrations: [GoogleIntegration]) -> GoogleIntegration {
        integrations.sorted {
            let leftScore = completenessScore($0)
            let rightScore = completenessScore($1)
            if leftScore != rightScore {
                return leftScore > rightScore
            }
            return $0.id.uuidString < $1.id.uuidString
        }[0]
    }

    func completenessScore(_ integration: GoogleIntegration) -> Int {
        var score = 0
        if nonEmpty(integration.refreshToken) != nil { score += 4 }
        if nonEmpty(integration.spreadsheetId) != nil { score += 4 }
        if integration.isEnabled { score += 2 }
        if nonEmpty(integration.googleUserId) != nil { score += 1 }
        return score
    }

    func mergeMissingValues(into primary: GoogleIntegration, from candidates: [GoogleIntegration]) {
        let rankedCandidates = candidates.sorted {
            let leftScore = completenessScore($0)
            let rightScore = completenessScore($1)
            if leftScore != rightScore {
                return leftScore > rightScore
            }
            return $0.id.uuidString < $1.id.uuidString
        }

        if nonEmpty(primary.refreshToken) == nil,
           let refreshToken = rankedCandidates.compactMap({ nonEmpty($0.refreshToken) }).first {
            primary.refreshToken = refreshToken
        }

        if nonEmpty(primary.spreadsheetId) == nil,
           let spreadsheetId = rankedCandidates.compactMap({ nonEmpty($0.spreadsheetId) }).first {
            primary.spreadsheetId = spreadsheetId
        }

        if nonEmpty(primary.googleUserId) == nil,
           let googleUserId = rankedCandidates.compactMap({ nonEmpty($0.googleUserId) }).first {
            primary.googleUserId = googleUserId
        }

        if !primary.isEnabled, rankedCandidates.contains(where: \.isEnabled) {
            primary.isEnabled = true
        }
    }

    func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
