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

    public func getOrCreateUserSettings() async throws -> UserSettings {
        var descriptor = FetchDescriptor<UserSettings>()
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            return existing
        }
        let settings = UserSettings.default()
        context.insert(settings)
        try context.save()
        return settings
    }

    public func updateUserSettings(_ settings: UserSettings) async throws -> UserSettings {
        // If an object with this id exists in the store, update fields; otherwise insert.
        var descriptor = FetchDescriptor<UserSettings>(
            predicate: #Predicate { $0.id == settings.id }
        )
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            existing.glucoseUnit = settings.glucoseUnit
            existing.bpSystolicMin = settings.bpSystolicMin
            existing.bpSystolicMax = settings.bpSystolicMax
            existing.bpDiastolicMin = settings.bpDiastolicMin
            existing.bpDiastolicMax = settings.bpDiastolicMax
            existing.glucoseMin = settings.glucoseMin
            existing.glucoseMax = settings.glucoseMax
            existing.breakfastTime = settings.breakfastTime
            existing.lunchTime = settings.lunchTime
            existing.dinnerTime = settings.dinnerTime
            existing.bedtimeSlotEnabled = settings.bedtimeSlotEnabled
            existing.bpTimes = settings.bpTimes
            existing.bpActiveWeekdays = settings.bpActiveWeekdays
            existing.enableBeforeMeal = settings.enableBeforeMeal
            existing.enableAfterMeal2h = settings.enableAfterMeal2h
            existing.enableBedtime = settings.enableBedtime
            existing.enableDailyCycleMode = settings.enableDailyCycleMode
            existing.currentCycleIndex = settings.currentCycleIndex
            try context.save()
            return existing
        } else {
            context.insert(settings)
            try context.save()
            return settings
        }
    }
}
