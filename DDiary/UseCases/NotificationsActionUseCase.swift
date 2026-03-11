import Foundation
import OSLog

/// Handles quick actions from notification responses (snooze / skip).
/// This type operates only on Sendable data and calls the NotificationsRepository helpers.
@MainActor
public final class NotificationsActionUseCase {
    private enum UserSurfacePolicy: String {
        case suppressed
    }

    private let notificationsRepository: any NotificationsRepository
    private let analyticsRepository: any AnalyticsRepository
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "DDiary",
        category: "NotificationsActionUseCase"
    )

    public init(
        notificationsRepository: any NotificationsRepository,
        analyticsRepository: any AnalyticsRepository
    ) {
        self.notificationsRepository = notificationsRepository
        self.analyticsRepository = analyticsRepository
    }

    /// Snooze any notification by scheduling a one-off reminder after `minutes`.
    /// The caller must provide a suitable title/body/category.
    public func snooze(
        originalIdentifier: String,
        minutes: Int,
        title: String,
        body: String,
        categoryIdentifier: String,
        mealSlotRawValue: String?,
        measurementTypeRawValue: String?
    ) async {
        await notificationsRepository.snooze(
            originalIdentifier: originalIdentifier,
            minutes: minutes,
            title: title,
            body: body,
            categoryIdentifier: categoryIdentifier,
            mealSlotRawValue: mealSlotRawValue,
            measurementTypeRawValue: measurementTypeRawValue
        )
    }

    /// Skip the current reminder instance: cancel it from the notification center
    /// and log analytics. Does not alter the recurring schedule.
    public func skip(identifier: String, categoryIdentifier: String) async {
        await notificationsRepository.cancel(withIdentifier: identifier)
        guard let kind = analyticsKind(for: categoryIdentifier) else { return }
        await analyticsRepository.logScheduleUpdated(kind: kind)
    }

    private func analyticsKind(for categoryIdentifier: String) -> AnalyticsScheduleKind? {
        switch categoryIdentifier {
        case UserNotificationsRepository.IDs.bpCategory:
            return .bloodPressure
        case
            UserNotificationsRepository.IDs.glucoseBeforeCategory,
            UserNotificationsRepository.IDs.glucoseAfterCategory,
            UserNotificationsRepository.IDs.glucoseBedtimeCategory:
            return .glucose
        default:
            return nil
        }
    }

    private func log(_ error: Error, operation: String, policy: UserSurfacePolicy) {
        logger.error(
            "\(operation, privacy: .public) failed. user_surface=\(policy.rawValue, privacy: .public) error=\(String(describing: error), privacy: .public)"
        )
    }
}
