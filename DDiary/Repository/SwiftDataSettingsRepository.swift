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
        guard let settings = try resolveSingleton(createIfMissing: true) else {
            throw SettingsRepositoryError.failedToResolveSingleton
        }
        return settings
    }

    func save(_ settings: UserSettings) async throws {
        guard let primary = try resolveSingleton(createIfMissing: true) else {
            throw SettingsRepositoryError.failedToResolveSingleton
        }
        if primary !== settings {
            copySettingsValues(from: settings, to: primary)
        }
        primary.singletonKey = UserSettings.singletonRecordKey
        try context.save()
    }

    func update(_ settings: UserSettings) async throws {
        try await save(settings)
    }
}

private enum SettingsRepositoryError: Error {
    case failedToResolveSingleton
}

private extension SwiftDataSettingsRepository {
    func resolveSingleton(createIfMissing: Bool) throws -> UserSettings? {
        let singletonKey = UserSettings.singletonRecordKey
        let singletonDescriptor = FetchDescriptor<UserSettings>(
            predicate: #Predicate { $0.singletonKey == singletonKey }
        )
        let keyedRecords = try context.fetch(singletonDescriptor)

        if let resolved = try collapseToDeterministicSingleton(from: keyedRecords) {
            return resolved
        }

        let allRecords = try context.fetch(FetchDescriptor<UserSettings>())
        guard !allRecords.isEmpty else {
            guard createIfMissing else { return nil }
            let settings = UserSettings.default()
            settings.singletonKey = UserSettings.singletonRecordKey
            context.insert(settings)
            try context.save()
            return settings
        }

        let primary = deterministicPrimary(from: allRecords)
        primary.singletonKey = UserSettings.singletonRecordKey
        for duplicate in allRecords where duplicate !== primary { context.delete(duplicate) }
        try context.save()
        return primary
    }

    func collapseToDeterministicSingleton(from candidates: [UserSettings]) throws -> UserSettings? {
        guard !candidates.isEmpty else { return nil }
        let primary = deterministicPrimary(from: candidates)
        primary.singletonKey = UserSettings.singletonRecordKey
        for duplicate in candidates where duplicate !== primary { context.delete(duplicate) }
        if candidates.count > 1 {
            try context.save()
        }
        return primary
    }

    func deterministicPrimary(from candidates: [UserSettings]) -> UserSettings {
        candidates.sorted(by: isPreferredPrimary).first!
    }

    func isPreferredPrimary(_ lhs: UserSettings, _ rhs: UserSettings) -> Bool {
        if lhs.id == UserSettings.singletonRecordID, rhs.id != UserSettings.singletonRecordID { return true }
        if rhs.id == UserSettings.singletonRecordID, lhs.id != UserSettings.singletonRecordID { return false }
        if lhs.id != rhs.id {
            return lhs.id.uuidString < rhs.id.uuidString
        }
        return stableModelIdentifier(lhs) > stableModelIdentifier(rhs)
    }

    func stableModelIdentifier(_ model: UserSettings) -> String {
        String(describing: model.persistentModelID)
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
