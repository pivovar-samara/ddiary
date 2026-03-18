import Foundation
import OSLog

/// Minimal cycle-mode helper for glucose measurements.
/// Keeps all mutations on the main actor because it touches SwiftData via SettingsRepository.
///
/// **Design:** `dailyCycleAnchorDate` is set when cycle mode is first enabled. When the user
/// reschedules today's slot, the anchor is updated to `startOfDay(today) - newStep.rawValue days`
/// so that all subsequent days automatically follow the new sequence. The `cycleOverrides`
/// dictionary is pruned on each mutation but no longer written to for today's slot; the anchor
/// is the single source of truth for the cycle position.
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

    /// No-op. The cycle advances naturally as calendar days pass; no anchor mutation is needed.
    /// Retained for API compatibility; callers may be removed in a follow-up.
    public func advanceIfEnabled(today: Date = Date()) async {}

    /// Sets the current daily cycle target to a specific meal slot if cycle mode is enabled.
    /// Updates the anchor date so that today equals the chosen slot and all subsequent days
    /// continue naturally from it.
    /// Rejects slots that are not in the active cycle (e.g. `.none` when bedtime is disabled).
    public func setTarget(_ meal: MealSlot, today: Date = Date()) async {
        do {
            let settings = try await settingsRepository.getOrCreate()
            guard settings.enableDailyCycleMode else { return }
            let order = cycleOrder(from: settings)
            guard order.contains(meal) else { return }
            guard let targetStep = step(for: meal) else { return }
            let calendar = Calendar.current
            settings.dailyCycleAnchorDate = updatedAnchorDate(for: targetStep, today: today, calendar: calendar)
            var overrides = GlucoseCyclePlanner.pruneOverrides(
                settings.cycleOverrides, today: today, calendar: calendar
            )
            // Anchor is now the source of truth. Remove any stale per-day override for today
            // so it cannot shadow the new anchor when GlucoseCyclePlanner.step() is called.
            overrides.removeValue(forKey: GlucoseCyclePlanner.dateKey(for: today, calendar: calendar))
            settings.cycleOverrides = overrides
            try await settingsRepository.save(settings)
            await analyticsRepository.logScheduleUpdated(kind: .glucose)
        } catch {
            log(error, operation: "setTarget", policy: .suppressed)
        }
    }

    /// Returns "switch to" options in daily cycle mode in canonical order:
    /// breakfast, lunch, dinner, bedtime; excluding the current slot.
    public func availableForwardTargetsForToday(today: Date = Date()) async -> [MealSlot] {
        do {
            let settings = try await settingsRepository.getOrCreate()
            guard settings.enableDailyCycleMode else { return [] }

            let calendar = Calendar.current
            let referenceDay = calendar.startOfDay(for: today)
            let anchorDate = settings.dailyCycleAnchorDate
                ?? GlucoseCyclePlanner.fallbackAnchorDate(
                    currentCycleIndex: settings.currentCycleIndex,
                    referenceDate: today,
                    calendar: calendar
                )
            let currentStep = GlucoseCyclePlanner.step(
                on: referenceDay,
                anchorDate: anchorDate,
                overrides: settings.cycleOverrides,
                calendar: calendar
            )
            let order = cycleOrder(from: settings)
            let currentSlot = cycleSlot(for: currentStep)

            return order.filter { $0 != currentSlot }
        } catch {
            log(error, operation: "availableForwardTargetsForToday", policy: .suppressed)
            return []
        }
    }

    /// Sets today's cycle target to a chosen slot.
    /// Updates the anchor date so that today equals the chosen slot and all subsequent days
    /// continue naturally from it. Returns `true` when the target was applied.
    public func setTodayTarget(_ meal: MealSlot, today: Date = Date()) async -> Bool {
        do {
            let settings = try await settingsRepository.getOrCreate()
            guard settings.enableDailyCycleMode else { return false }
            guard step(for: meal) != nil else { return false }

            let availableTargets = await availableForwardTargetsForToday(today: today)
            guard availableTargets.contains(meal) else { return false }

            guard let targetStep = step(for: meal) else { return false }
            let calendar = Calendar.current
            settings.dailyCycleAnchorDate = updatedAnchorDate(for: targetStep, today: today, calendar: calendar)
            var overrides = GlucoseCyclePlanner.pruneOverrides(
                settings.cycleOverrides, today: today, calendar: calendar
            )
            overrides.removeValue(forKey: GlucoseCyclePlanner.dateKey(for: today, calendar: calendar))
            settings.cycleOverrides = overrides
            try await settingsRepository.save(settings)
            await analyticsRepository.logScheduleUpdated(kind: .glucose)
            return true
        } catch {
            log(error, operation: "setTodayTarget", policy: .suppressed)
            return false
        }
    }

    /// Returns the current target slot if cycle mode is enabled; otherwise nil.
    public func currentTarget(today: Date = Date()) async -> MealSlot? {
        do {
            let settings = try await settingsRepository.getOrCreate()
            guard settings.enableDailyCycleMode else { return nil }
            let calendar = Calendar.current
            let referenceDay = calendar.startOfDay(for: today)
            let anchorDate = settings.dailyCycleAnchorDate
                ?? GlucoseCyclePlanner.fallbackAnchorDate(
                    currentCycleIndex: settings.currentCycleIndex,
                    referenceDate: today,
                    calendar: calendar
                )
            let currentStep = GlucoseCyclePlanner.step(
                on: referenceDay,
                anchorDate: anchorDate,
                overrides: settings.cycleOverrides,
                calendar: calendar
            )
            return cycleSlot(for: currentStep)
        } catch {
            log(error, operation: "currentTarget", policy: .suppressed)
            return nil
        }
    }

    /// Advances today's cycle step by +1 and updates the anchor so all subsequent days
    /// continue from the new position: breakfast → lunch → dinner → bedtime → breakfast.
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
            let currentStep = GlucoseCyclePlanner.step(
                on: referenceDay,
                anchorDate: anchorDate,
                overrides: settings.cycleOverrides,
                calendar: calendar
            )
            let order = cycleOrder(from: settings)
            guard !order.isEmpty else { return false }
            let currentSlot = cycleSlot(for: currentStep, settings: settings)
            guard let currentIndex = order.firstIndex(of: currentSlot) else { return false }
            let nextSlot = order[(currentIndex + 1) % order.count]
            guard let nextStep = step(for: nextSlot) else { return false }
            settings.dailyCycleAnchorDate = updatedAnchorDate(for: nextStep, today: today, calendar: calendar)
            var overrides = GlucoseCyclePlanner.pruneOverrides(
                settings.cycleOverrides, today: today, calendar: calendar
            )
            overrides.removeValue(forKey: GlucoseCyclePlanner.dateKey(for: today, calendar: calendar))
            settings.cycleOverrides = overrides
            try await settingsRepository.save(settings)
            return true
        } catch {
            log(error, operation: "shiftTodayForward", policy: .suppressed)
            return false
        }
    }

    // MARK: - Helpers

    private func cycleOrder(from settings: UserSettings) -> [MealSlot] {
        var order: [MealSlot] = [.breakfast, .lunch, .dinner]
        if settings.bedtimeSlotEnabled {
            order.append(.none)
        }
        return order
    }

    private func cycleSlot(for step: GlucoseCycleStep, settings: UserSettings? = nil) -> MealSlot {
        switch step {
        case .breakfastDay:
            return .breakfast
        case .lunchDay:
            return .lunch
        case .dinnerDay:
            return .dinner
        case .bedtimeDay:
            // When bedtime is disabled the planner still uses a 4-step cycle, so currentStep can
            // resolve to .bedtimeDay even though the slot isn't in the active order.  Normalise to
            // .breakfast (index 3 % 3 == 0) so the shift never gets stuck on a hidden step.
            if let settings, !settings.bedtimeSlotEnabled { return .breakfast }
            return .none
        }
    }

    private func step(for slot: MealSlot) -> GlucoseCycleStep? {
        switch slot {
        case .breakfast:
            return .breakfastDay
        case .lunch:
            return .lunchDay
        case .dinner:
            return .dinnerDay
        case .none:
            return .bedtimeDay
        }
    }

    /// Returns an anchor date such that `GlucoseCyclePlanner.step(on: today, anchorDate:)`
    /// yields `step`, and tomorrow yields the next step in the cycle.
    private func updatedAnchorDate(for step: GlucoseCycleStep, today: Date, calendar: Calendar) -> Date {
        let startOfToday = calendar.startOfDay(for: today)
        return calendar.date(byAdding: .day, value: -step.rawValue, to: startOfToday) ?? startOfToday
    }

    private func log(_ error: Error, operation: String, policy: UserSurfacePolicy) {
        logger.error(
            "\(operation, privacy: .public) failed. user_surface=\(policy.rawValue, privacy: .public) error=\(String(describing: error), privacy: .public)"
        )
    }
}
