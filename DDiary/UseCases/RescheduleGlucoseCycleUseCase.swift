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
    /// Shifts the anchor back by one day so today maps to the next cycle step.
    public func advanceIfEnabled(today: Date = Date()) async {
        do {
            let settings = try await settingsRepository.getOrCreate()
            guard settings.enableDailyCycleMode else { return }
            shiftAnchorBackOneDay(for: settings, today: today, calendar: .current)
            try await settingsRepository.save(settings)
            await analyticsRepository.logScheduleUpdated(kind: .glucose)
        } catch {
            log(error, operation: "advanceIfEnabled", policy: .suppressed)
        }
    }

    /// Sets the current daily cycle target to a specific meal slot if cycle mode is enabled.
    /// Adjusts the anchor so that today maps to the requested slot.
    /// Rejects slots that are not in the active cycle (e.g. `.none` when bedtime is disabled).
    public func setTarget(_ meal: MealSlot, today: Date = Date()) async {
        do {
            let settings = try await settingsRepository.getOrCreate()
            guard settings.enableDailyCycleMode else { return }
            let order = cycleOrder(from: settings)
            guard order.contains(meal) else { return }
            guard let targetStep = step(for: meal) else { return }
            let calendar = Calendar.current
            let referenceDay = calendar.startOfDay(for: today)
            let shiftedAnchor = calendar.date(byAdding: .day, value: -targetStep.rawValue, to: referenceDay) ?? referenceDay
            settings.dailyCycleAnchorDate = shiftedAnchor
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
            let currentStep = GlucoseCyclePlanner.step(on: referenceDay, anchorDate: anchorDate, calendar: calendar)
            let order = cycleOrder(from: settings)
            let currentSlot = cycleSlot(for: currentStep)

            return order.filter { $0 != currentSlot }
        } catch {
            log(error, operation: "availableForwardTargetsForToday", policy: .suppressed)
            return []
        }
    }

    /// Sets today's cycle target to a chosen later slot by changing the cycle anchor.
    /// Returns `true` when the target was applied.
    public func setTodayTarget(_ meal: MealSlot, today: Date = Date()) async -> Bool {
        do {
            let settings = try await settingsRepository.getOrCreate()
            guard settings.enableDailyCycleMode else { return false }
            guard step(for: meal) != nil else { return false }

            let availableTargets = await availableForwardTargetsForToday(today: today)
            guard availableTargets.contains(meal) else { return false }

            let calendar = Calendar.current
            let referenceDay = calendar.startOfDay(for: today)
            guard let targetStep = step(for: meal) else { return false }
            let shiftedAnchor = calendar.date(byAdding: .day, value: -targetStep.rawValue, to: referenceDay) ?? referenceDay

            settings.dailyCycleAnchorDate = shiftedAnchor
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
            let currentStep = GlucoseCyclePlanner.step(on: referenceDay, anchorDate: anchorDate, calendar: calendar)
            return cycleSlot(for: currentStep)
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
            shiftAnchorBackOneDay(for: settings, today: today, calendar: .current)
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

    private func cycleSlot(for step: GlucoseCycleStep) -> MealSlot {
        switch step {
        case .breakfastDay:
            return .breakfast
        case .lunchDay:
            return .lunch
        case .dinnerDay:
            return .dinner
        case .bedtimeDay:
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

    /// Resolves the current anchor (falling back to the legacy index when nil) and shifts it
    /// back by one calendar day, making today map to the next cycle step.
    private func shiftAnchorBackOneDay(for settings: UserSettings, today: Date, calendar: Calendar) {
        let anchorDate = settings.dailyCycleAnchorDate
            ?? GlucoseCyclePlanner.fallbackAnchorDate(
                currentCycleIndex: settings.currentCycleIndex,
                referenceDate: today,
                calendar: calendar
            )
        settings.dailyCycleAnchorDate = calendar.date(byAdding: .day, value: -1, to: anchorDate) ?? anchorDate
    }

    private func log(_ error: Error, operation: String, policy: UserSurfacePolicy) {
        logger.error(
            "\(operation, privacy: .public) failed. user_surface=\(policy.rawValue, privacy: .public) error=\(String(describing: error), privacy: .public)"
        )
    }
}
