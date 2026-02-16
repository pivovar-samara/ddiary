import Foundation
import OSLog

/// Minimal cycle-mode helper for glucose measurements.
/// Keeps all mutations on the main actor because it touches SwiftData via SettingsRepository.
@MainActor
public final class RescheduleGlucoseCycleUseCase {
    private enum UserSurfacePolicy: String {
        case suppressed
    }

    private let settingsRepository: any SettingsRepository
    private let analyticsRepository: any AnalyticsRepository
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "DDiary",
        category: "RescheduleGlucoseCycleUseCase"
    )

    public init(
        settingsRepository: any SettingsRepository,
        analyticsRepository: any AnalyticsRepository
    ) {
        self.settingsRepository = settingsRepository
        self.analyticsRepository = analyticsRepository
    }

    /// Advances the daily cycle target by one position if cycle mode is enabled.
    /// Sequence: breakfast → lunch → dinner → bedtime → breakfast → ...
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
            log(error, operation: "advanceIfEnabled", policy: .suppressed)
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
            log(error, operation: "setTarget", policy: .suppressed)
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
            log(error, operation: "currentTarget", policy: .suppressed)
            return nil
        }
    }

    /// Shift today's cycle step by +1 day:
    /// breakfast -> lunch -> dinner -> bedtime -> breakfast.
    /// Returns `true` if the shift was applied.
    public func shiftTodayForward(today: Date = Date()) async -> Bool {
        do {
            let settings = try await settingsRepository.getOrCreate()
            guard settings.enableDailyCycleMode else { return false }
            let calendar = Calendar.current
            let referenceDay = calendar.startOfDay(for: today)
            let anchorDate = settings.dailyCycleAnchorDate
                ?? GlucoseCyclePlanner.fallbackAnchorDate(
                    currentCycleIndex: settings.currentCycleIndex,
                    referenceDate: today,
                    calendar: calendar
                )
            let shiftedAnchor = calendar.date(byAdding: .day, value: -1, to: anchorDate) ?? anchorDate
            settings.dailyCycleAnchorDate = shiftedAnchor
            let updatedStep = GlucoseCyclePlanner.step(on: referenceDay, anchorDate: shiftedAnchor, calendar: calendar)
            settings.currentCycleIndex = updatedStep.rawValue
            try await settingsRepository.save(settings)
            return true
        } catch {
            log(error, operation: "shiftTodayForward", policy: .suppressed)
            return false
        }
    }

    // MARK: - Helpers
    private func cycleOrder(from settings: UserSettings) -> [MealSlot] {
        _ = settings
        return [.breakfast, .lunch, .dinner, .none]
    }

    private func positiveModulo(_ value: Int, _ modulus: Int) -> Int {
        let remainder = value % modulus
        return remainder >= 0 ? remainder : remainder + modulus
    }

    private func log(_ error: Error, operation: String, policy: UserSurfacePolicy) {
        logger.error(
            "\(operation, privacy: .public) failed. user_surface=\(policy.rawValue, privacy: .public) error=\(String(describing: error), privacy: .public)"
        )
    }
}
