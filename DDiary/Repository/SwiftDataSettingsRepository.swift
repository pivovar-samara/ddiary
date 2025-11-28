//
//  SwiftDataSettingsRepository.swift
//  DDiary
//
//  Created by Assistant on 26.11.25.
//

import Foundation
import SwiftData

@MainActor
public final class SwiftDataSettingsRepository: SettingsRepository {
    private let context: ModelContext

    public init(modelContext: ModelContext) {
        self.context = modelContext
    }

    public func getOrCreateUserSettings() async throws -> UserSettingsDTO {
        var descriptor = FetchDescriptor<UserSettings>()
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            return UserSettingsDTO(model: existing)
        }
        let settings = UserSettings.default()
        context.insert(settings)
        try context.save()
        return UserSettingsDTO(model: settings)
    }

    public func updateUserSettings(_ settings: UserSettingsDTO) async throws -> UserSettingsDTO {
        // If an object with this id exists in the store, update fields; otherwise insert.
        var descriptor = FetchDescriptor<UserSettings>(
            predicate: #Predicate { $0.id == settings.id }
        )
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            settings.applying(to: existing)
            try context.save()
            return UserSettingsDTO(model: existing)
        } else {
            let model = settings.makeModel()
            context.insert(model)
            try context.save()
            return UserSettingsDTO(model: model)
        }
    }
}
