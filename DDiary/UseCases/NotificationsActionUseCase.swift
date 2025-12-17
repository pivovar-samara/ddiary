import Foundation

/// Handles quick actions from notification responses (snooze / move / skip).
/// This type operates only on Sendable data and calls the NotificationsRepository helpers.
@MainActor
public final class NotificationsActionUseCase {
    private let settingsRepository: any SettingsRepository
    private let notificationsRepository: any NotificationsRepository
    private let analyticsRepository: any AnalyticsRepository

    public init(
        settingsRepository: any SettingsRepository,
        notificationsRepository: any NotificationsRepository,
        analyticsRepository: any AnalyticsRepository
    ) {
        self.settingsRepository = settingsRepository
        self.notificationsRepository = notificationsRepository
        self.analyticsRepository = analyticsRepository
    }

    /// Snooze any notification by scheduling a one-off reminder after `minutes`.
    /// The caller must provide a suitable title/body/category.
    public func snooze(originalIdentifier: String, minutes: Int, title: String, body: String, categoryIdentifier: String) async {
        await notificationsRepository.snooze(
            originalIdentifier: originalIdentifier,
            minutes: minutes,
            title: title,
            body: body,
            categoryIdentifier: categoryIdentifier
        )
    }

    /// Move a before-breakfast notification to lunch or dinner for today.
    /// Computes the target time from settings and schedules a one-off notification at that time.
    public func moveBeforeBreakfast(to meal: MealSlot) async {
        do {
            let settings = try await settingsRepository.getOrCreate()
            let comps: DateComponents
            let title: String
            switch meal {
            case .lunch:
                comps = DateComponents(hour: settings.lunchHour, minute: settings.lunchMinute)
                title = "Glucose — Before Lunch"
            case .dinner:
                comps = DateComponents(hour: settings.dinnerHour, minute: settings.dinnerMinute)
                title = "Glucose — Before Dinner"
            default:
                return
            }
            if let date = Calendar.current.nextDate(after: Date(), matching: comps, matchingPolicy: .nextTime, direction: .forward) {
                let id = "ddiary.glucose.before.move.\(meal.rawValue)" // one-off id
                await notificationsRepository.scheduleOneOff(
                    at: date,
                    identifier: id,
                    title: title,
                    body: "Rescheduled from breakfast.",
                    categoryIdentifier: UserNotificationsRepository.IDs.glucoseBeforeCategory
                )
            }
        } catch {
            // v1: silently ignore
        }
    }

    /// Placeholder for skip logic — in v1 we just log analytics.
    public func skip() async {
        await analyticsRepository.logScheduleUpdated(kind: .glucose)
    }
}
