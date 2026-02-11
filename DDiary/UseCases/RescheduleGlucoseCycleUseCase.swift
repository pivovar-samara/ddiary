import Foundation

/// Minimal cycle-mode helper for glucose measurements.
/// Keeps all mutations on the main actor because it touches SwiftData via SettingsRepository.
@MainActor
public final class RescheduleGlucoseCycleUseCase {
    private let settingsRepository: any SettingsRepository
    private let analyticsRepository: any AnalyticsRepository

    public init(
        settingsRepository: any SettingsRepository,
        analyticsRepository: any AnalyticsRepository
    ) {
        self.settingsRepository = settingsRepository
        self.analyticsRepository = analyticsRepository
    }

    /// Advances the daily cycle target by one position if cycle mode is enabled.
    /// Sequence: breakfast → lunch → dinner → (bedtime if enabled) → breakfast → ...
    public func advanceIfEnabled() async {
        do {
            let settings = try await settingsRepository.getOrCreate()
            guard settings.enableDailyCycleMode else { return }
            let order = cycleOrder(from: settings)
            guard !order.isEmpty else { return }
            let current = positiveModulo(settings.currentCycleIndex, order.count)
            let next = (current + 1) % order.count
            settings.currentCycleIndex = next
            try await settingsRepository.save(settings)
            await analyticsRepository.logScheduleUpdated(kind: .glucose)
        } catch {
            // v1: fail silently; consider logging in a later release
        }
    }

    /// Sets the current daily cycle target to a specific meal slot if cycle mode is enabled.
    public func setTarget(_ meal: MealSlot) async {
        do {
            let settings = try await settingsRepository.getOrCreate()
            guard settings.enableDailyCycleMode else { return }
            let order = cycleOrder(from: settings)
            guard let idx = order.firstIndex(of: meal) else { return }
            settings.currentCycleIndex = idx
            try await settingsRepository.save(settings)
            await analyticsRepository.logScheduleUpdated(kind: .glucose)
        } catch {
            // v1: ignore
        }
    }

    /// Returns the current target slot if cycle mode is enabled; otherwise nil.
    public func currentTarget() async -> MealSlot? {
        do {
            let settings = try await settingsRepository.getOrCreate()
            guard settings.enableDailyCycleMode else { return nil }
            let order = cycleOrder(from: settings)
            guard !order.isEmpty else { return nil }
            let idx = positiveModulo(settings.currentCycleIndex, order.count)
            return order[idx]
        } catch {
            return nil
        }
    }

    // MARK: - Helpers
    private func cycleOrder(from settings: UserSettings) -> [MealSlot] {
        var order: [MealSlot] = [.breakfast, .lunch, .dinner]
        if settings.bedtimeSlotEnabled {
            order.append(.none) // use `.none` to denote bedtime slot in v1
        }
        return order
    }

    private func positiveModulo(_ value: Int, _ modulus: Int) -> Int {
        let remainder = value % modulus
        return remainder >= 0 ? remainder : remainder + modulus
    }
}
