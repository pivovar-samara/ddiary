import Foundation
import OSLog

/// Minimal cycle-mode helper for glucose measurements.
/// Keeps all mutations on the main actor because it touches SwiftData via SettingsRepository.
///
/// **Design:** `dailyCycleAnchorDate` is set when cycle mode is first enabled. When the user
/// reschedules today's slot, the anchor is updated to `startOfDay(today) - newStep.rawValue days`
/// so that all subsequent days automatically follow the new sequence. On every anchor update,
/// `cycleOverrides` entries for today and all future dates are cleared (in addition to the
/// normal 30-day pruning of past entries) so no stale override can shadow the new anchor.
/// The anchor is the single source of truth for the cycle position.
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
            guard applyAnchorUpdate(to: settings, step: targetStep, today: today, calendar: calendar) else { return }
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
            guard applyAnchorUpdate(to: settings, step: targetStep, today: today, calendar: calendar) else { return false }
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
            guard applyAnchorUpdate(to: settings, step: nextStep, today: today, calendar: calendar) else { return false }
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

    /// Computes the new anchor date and cleaned overrides for an anchor-change operation,
    /// compares them against the current settings values, and—if anything differs—writes the
    /// new values into `settings` and returns `true`. Returns `false` without touching
    /// `settings` when the computed state is identical to the existing state (no-op).
    ///
    /// This prevents unnecessary SwiftData writes and spurious analytics events when the
    /// user reschedules to the slot that is already current.
    ///
    /// The new anchor makes `today` resolve to `step`; subsequent days follow naturally.
    /// Past overrides older than 30 days are pruned; overrides for today and future dates
    /// are dropped so none can shadow the new anchor.
    ///
    /// `calendar` must be the same instance the caller already used for any `step(on:)` lookup
    /// in the same operation, ensuring anchor computation and step derivation stay consistent.
    @discardableResult
    private func applyAnchorUpdate(
        to settings: UserSettings,
        step: GlucoseCycleStep,
        today: Date,
        calendar: Calendar
    ) -> Bool {
        let startOfToday = calendar.startOfDay(for: today)
        let newAnchor: Date
        if let anchorDate = calendar.date(byAdding: .day, value: -step.rawValue, to: startOfToday) {
            newAnchor = anchorDate
        } else {
            assertionFailure("applyAnchorUpdate: calendar.date(byAdding:) returned nil — this should never happen for a valid date")
            logger.error("applyAnchorUpdate failed to compute anchor date for step \(step.rawValue, privacy: .public); falling back to startOfToday")
            newAnchor = startOfToday
        }
        let pruned = GlucoseCyclePlanner.pruneOverrides(
            settings.cycleOverrides, today: today, calendar: calendar
        )
        let newOverrides = GlucoseCyclePlanner.dropFutureAndTodayOverrides(
            pruned, today: today, calendar: calendar
        )
        guard newAnchor != settings.dailyCycleAnchorDate || newOverrides != settings.cycleOverrides else {
            return false
        }
        settings.dailyCycleAnchorDate = newAnchor
        settings.cycleOverrides = newOverrides
        return true
    }

    private func log(_ error: Error, operation: String, policy: UserSurfacePolicy) {
        logger.error(
            "\(operation, privacy: .public) failed. user_surface=\(policy.rawValue, privacy: .public) error=\(String(describing: error), privacy: .public)"
        )
    }
}
