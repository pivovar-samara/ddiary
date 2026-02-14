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
        if let existing = try resolveSingleton(createIfMissing: true) {
            return existing
        }
        let settings = UserSettings.default()
        context.insert(settings)
        try context.save()
        return settings
    }

    func save(_ settings: UserSettings) async throws {
        if let primary = try resolveSingleton(createIfMissing: false) {
            if primary !== settings {
                copySettingsValues(from: settings, to: primary)
            }
        } else {
            context.insert(settings)
        }
        try context.save()
    }

    func update(_ settings: UserSettings) async throws {
        try await save(settings)
    }
}

private extension SwiftDataSettingsRepository {
    func resolveSingleton(createIfMissing: Bool) throws -> UserSettings? {
        let descriptor = FetchDescriptor<UserSettings>()
        let all = try context.fetch(descriptor)
        guard !all.isEmpty else {
            guard createIfMissing else { return nil }
            let settings = UserSettings.default()
            context.insert(settings)
            try context.save()
            return settings
        }

        guard all.count > 1 else {
            return all[0]
        }

        let primary = selectPrimarySettings(from: all)
        for duplicate in all where duplicate !== primary {
            context.delete(duplicate)
        }
        try context.save()
        return primary
    }

    func selectPrimarySettings(from all: [UserSettings]) -> UserSettings {
        all.sorted {
            let leftScore = customizationScore($0)
            let rightScore = customizationScore($1)
            if leftScore != rightScore {
                return leftScore > rightScore
            }
            return $0.id.uuidString < $1.id.uuidString
        }[0]
    }

    func customizationScore(_ settings: UserSettings) -> Int {
        let defaults = UserSettings.default()
        var score = 0

        if settings.glucoseUnit != defaults.glucoseUnit { score += 1 }

        if settings.bpSystolicMin != defaults.bpSystolicMin { score += 1 }
        if settings.bpSystolicMax != defaults.bpSystolicMax { score += 1 }
        if settings.bpDiastolicMin != defaults.bpDiastolicMin { score += 1 }
        if settings.bpDiastolicMax != defaults.bpDiastolicMax { score += 1 }

        if settings.glucoseMin != defaults.glucoseMin { score += 1 }
        if settings.glucoseMax != defaults.glucoseMax { score += 1 }

        if settings.breakfastHour != defaults.breakfastHour { score += 1 }
        if settings.breakfastMinute != defaults.breakfastMinute { score += 1 }
        if settings.lunchHour != defaults.lunchHour { score += 1 }
        if settings.lunchMinute != defaults.lunchMinute { score += 1 }
        if settings.dinnerHour != defaults.dinnerHour { score += 1 }
        if settings.dinnerMinute != defaults.dinnerMinute { score += 1 }
        if settings.bedtimeHour != defaults.bedtimeHour { score += 1 }
        if settings.bedtimeMinute != defaults.bedtimeMinute { score += 1 }

        if settings.bedtimeSlotEnabled != defaults.bedtimeSlotEnabled { score += 1 }
        if settings.enableBeforeMeal != defaults.enableBeforeMeal { score += 1 }
        if settings.enableAfterMeal2h != defaults.enableAfterMeal2h { score += 1 }
        if settings.enableBedtime != defaults.enableBedtime { score += 1 }
        if settings.enableDailyCycleMode != defaults.enableDailyCycleMode { score += 1 }
        if settings.currentCycleIndex != defaults.currentCycleIndex { score += 1 }

        if settings.bpTimes != defaults.bpTimes { score += 2 }
        if settings.bpActiveWeekdays != defaults.bpActiveWeekdays { score += 2 }

        return score
    }

    func copySettingsValues(from source: UserSettings, to target: UserSettings) {
        target.glucoseUnit = source.glucoseUnit

        target.bpSystolicMin = source.bpSystolicMin
        target.bpSystolicMax = source.bpSystolicMax
        target.bpDiastolicMin = source.bpDiastolicMin
        target.bpDiastolicMax = source.bpDiastolicMax

        target.glucoseMin = source.glucoseMin
        target.glucoseMax = source.glucoseMax

        target.breakfastHour = source.breakfastHour
        target.breakfastMinute = source.breakfastMinute
        target.lunchHour = source.lunchHour
        target.lunchMinute = source.lunchMinute
        target.dinnerHour = source.dinnerHour
        target.dinnerMinute = source.dinnerMinute
        target.bedtimeSlotEnabled = source.bedtimeSlotEnabled
        target.bedtimeHour = source.bedtimeHour
        target.bedtimeMinute = source.bedtimeMinute

        target.bpTimes = source.bpTimes
        target.bpActiveWeekdays = source.bpActiveWeekdays

        target.enableBeforeMeal = source.enableBeforeMeal
        target.enableAfterMeal2h = source.enableAfterMeal2h
        target.enableBedtime = source.enableBedtime
        target.enableDailyCycleMode = source.enableDailyCycleMode
        target.currentCycleIndex = source.currentCycleIndex
    }
}
