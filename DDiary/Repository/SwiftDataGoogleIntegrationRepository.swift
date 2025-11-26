//
//  SwiftDataGoogleIntegrationRepository.swift
//  DDiary
//
//  Created by Assistant on 26.11.25.
//

import Foundation
import SwiftData

@MainActor
public final class SwiftDataGoogleIntegrationRepository: GoogleIntegrationRepository {
    private let context: ModelContext

    public init(modelContext: ModelContext) {
        self.context = modelContext
    }

    public func getOrCreateGoogleIntegration() async throws -> GoogleIntegration {
        var descriptor = FetchDescriptor<GoogleIntegration>()
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            return existing
        }
        let integration = GoogleIntegration()
        context.insert(integration)
        try context.save()
        return integration
    }

    public func updateGoogleIntegration(_ integration: GoogleIntegration) async throws -> GoogleIntegration {
        var descriptor = FetchDescriptor<GoogleIntegration>(
            predicate: #Predicate { $0.id == integration.id }
        )
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            existing.spreadsheetId = integration.spreadsheetId
            existing.googleUserId = integration.googleUserId
            existing.refreshToken = integration.refreshToken
            existing.isEnabled = integration.isEnabled
            try context.save()
            return existing
        } else {
            context.insert(integration)
            try context.save()
            return integration
        }
    }

    public func clearTokensOnLogout() async throws {
        var descriptor = FetchDescriptor<GoogleIntegration>()
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            existing.refreshToken = nil
            existing.googleUserId = nil
            existing.isEnabled = false
            try context.save()
        }
    }
}
