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
        guard let integration = try resolveSingleton(createIfMissing: true) else {
            throw GoogleIntegrationRepositoryError.failedToResolveSingleton
        }
        return integration
    }

    func save(_ integration: GoogleIntegration) async throws {
        guard let primary = try resolveSingleton(createIfMissing: true) else {
            throw GoogleIntegrationRepositoryError.failedToResolveSingleton
        }
        if primary !== integration {
            copyIntegrationValues(from: integration, to: primary)
        }
        primary.singletonKey = GoogleIntegration.singletonRecordKey
        try context.save()
    }

    func update(_ integration: GoogleIntegration) async throws {
        try await save(integration)
    }

    func clearTokens(_ : GoogleIntegration) async throws {
        guard let primary = try resolveSingleton(createIfMissing: true) else {
            throw GoogleIntegrationRepositoryError.failedToResolveSingleton
        }
        primary.refreshToken = nil
        primary.spreadsheetId = nil
        primary.googleUserId = nil
        primary.isEnabled = false
        try context.save()
    }
}

private enum GoogleIntegrationRepositoryError: Error {
    case failedToResolveSingleton
}

private extension SwiftDataGoogleIntegrationRepository {
    func resolveSingleton(createIfMissing: Bool) throws -> GoogleIntegration? {
        let singletonKey = GoogleIntegration.singletonRecordKey
        let singletonDescriptor = FetchDescriptor<GoogleIntegration>(
            predicate: #Predicate { $0.singletonKey == singletonKey }
        )
        let keyedRecords = try context.fetch(singletonDescriptor)

        if let resolved = try collapseToDeterministicSingleton(from: keyedRecords) {
            return resolved
        }

        let allRecords = try context.fetch(FetchDescriptor<GoogleIntegration>())
        guard !allRecords.isEmpty else {
            guard createIfMissing else { return nil }
            let integration = GoogleIntegration()
            integration.singletonKey = GoogleIntegration.singletonRecordKey
            context.insert(integration)
            try context.save()
            return integration
        }

        let primary = deterministicPrimary(from: allRecords)
        mergeDuplicateValues(into: primary, from: allRecords)
        primary.singletonKey = GoogleIntegration.singletonRecordKey
        for duplicate in allRecords where duplicate !== primary {
            context.delete(duplicate)
        }
        try context.save()
        return primary
    }

    func collapseToDeterministicSingleton(from candidates: [GoogleIntegration]) throws -> GoogleIntegration? {
        guard !candidates.isEmpty else { return nil }
        let primary = deterministicPrimary(from: candidates)
        mergeDuplicateValues(into: primary, from: candidates)
        primary.singletonKey = GoogleIntegration.singletonRecordKey
        for duplicate in candidates where duplicate !== primary {
            context.delete(duplicate)
        }
        if candidates.count > 1 {
            try context.save()
        }
        return primary
    }

    func deterministicPrimary(from candidates: [GoogleIntegration]) -> GoogleIntegration {
        candidates.sorted(by: isPreferredPrimary).first!
    }

    func isPreferredPrimary(_ lhs: GoogleIntegration, _ rhs: GoogleIntegration) -> Bool {
        let lhsCompletenessScore = completenessScore(for: lhs)
        let rhsCompletenessScore = completenessScore(for: rhs)
        if lhsCompletenessScore != rhsCompletenessScore {
            return lhsCompletenessScore > rhsCompletenessScore
        }
        if lhs.id == GoogleIntegration.singletonRecordID, rhs.id != GoogleIntegration.singletonRecordID { return true }
        if rhs.id == GoogleIntegration.singletonRecordID, lhs.id != GoogleIntegration.singletonRecordID { return false }
        if lhs.id != rhs.id {
            return lhs.id.uuidString < rhs.id.uuidString
        }
        return stableModelIdentifier(lhs) > stableModelIdentifier(rhs)
    }

    func completenessScore(for integration: GoogleIntegration) -> Int {
        var score = 0
        if integration.isEnabled { score += 1 }
        if normalized(integration.refreshToken) != nil { score += 1 }
        if normalized(integration.spreadsheetId) != nil { score += 1 }
        if normalized(integration.googleUserId) != nil { score += 1 }
        return score
    }

    func stableModelIdentifier(_ model: GoogleIntegration) -> String {
        String(describing: model.persistentModelID)
    }

    func mergeDuplicateValues(into primary: GoogleIntegration, from candidates: [GoogleIntegration]) {
        for candidate in candidates where candidate !== primary {
            if primary.refreshToken == nil, let refreshToken = normalized(candidate.refreshToken) {
                primary.refreshToken = refreshToken
            }
            if primary.spreadsheetId == nil, let spreadsheetId = normalized(candidate.spreadsheetId) {
                primary.spreadsheetId = spreadsheetId
            }
            if primary.googleUserId == nil, let googleUserId = normalized(candidate.googleUserId) {
                primary.googleUserId = googleUserId
            }
            if !primary.isEnabled && candidate.isEnabled {
                primary.isEnabled = true
            }
        }
    }

    func copyIntegrationValues(from source: GoogleIntegration, to target: GoogleIntegration) {
        target.spreadsheetId = normalized(source.spreadsheetId)
        target.googleUserId = normalized(source.googleUserId)
        target.refreshToken = normalized(source.refreshToken)
        target.isEnabled = source.isEnabled
    }

    func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
