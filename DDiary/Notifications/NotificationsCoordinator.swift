import Foundation
import UserNotifications

@MainActor
protocol NotificationsActionHandling: AnyObject {
    func skip() async
    func snooze(originalIdentifier: String, minutes: Int, title: String, body: String, categoryIdentifier: String) async
    func moveBeforeBreakfast(to meal: MealSlot) async
}

extension NotificationsActionUseCase: NotificationsActionHandling {}

extension Notification.Name {
    nonisolated static let notificationQuickEntryRequested = Notification.Name("NotificationQuickEntryRequested")
}

enum NotificationQuickEntryTarget: Sendable, Equatable {
    case bloodPressure
    case glucose(mealSlot: MealSlot, measurementType: GlucoseMeasurementType)
}

struct NotificationQuickEntryRequest: Sendable, Equatable {
    let identifier: String
    let target: NotificationQuickEntryTarget
    let scheduledDate: Date?
}

@MainActor
protocol NotificationQuickEntryRouting: AnyObject {
    func routeToQuickEntry(context: NotificationActionContext)
}

@MainActor
final class NotificationQuickEntryRouter: NotificationQuickEntryRouting {
    static let shared = NotificationQuickEntryRouter()

    private let notificationCenter: NotificationCenter
    private var pendingRequest: NotificationQuickEntryRequest?

    init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
    }

    var hasPendingRequest: Bool {
        pendingRequest != nil
    }

    func consumePendingRequest() -> NotificationQuickEntryRequest? {
        defer { pendingRequest = nil }
        return pendingRequest
    }

    func routeToQuickEntry(context: NotificationActionContext) {
        guard let target = Self.decodeTarget(from: context) else { return }
        let scheduledDate = context.deliveredDate ?? Self.decodeScheduledDate(from: context.identifier)
        pendingRequest = NotificationQuickEntryRequest(
            identifier: context.identifier,
            target: target,
            scheduledDate: scheduledDate
        )
        notificationCenter.post(name: .notificationQuickEntryRequested, object: nil)
    }

    static func decodeTarget(from context: NotificationActionContext) -> NotificationQuickEntryTarget? {
        switch context.categoryIdentifier {
        case UserNotificationsRepository.IDs.bpCategory:
            return .bloodPressure
        case UserNotificationsRepository.IDs.glucoseBedtimeCategory:
            return .glucose(mealSlot: .none, measurementType: .bedtime)
        case UserNotificationsRepository.IDs.glucoseBeforeCategory:
            guard let mealSlot = decodeMealSlot(from: context) else { return nil }
            return .glucose(mealSlot: mealSlot, measurementType: .beforeMeal)
        case UserNotificationsRepository.IDs.glucoseAfterCategory:
            guard let mealSlot = decodeMealSlot(from: context) else { return nil }
            return .glucose(mealSlot: mealSlot, measurementType: .afterMeal2h)
        default:
            return nil
        }
    }

    private static func decodeMealSlot(from context: NotificationActionContext) -> MealSlot? {
        if let rawValue = context.mealSlotRawValue, let mealSlot = MealSlot(rawValue: rawValue) {
            return mealSlot
        }

        switch context.title {
        case L10n.notificationGlucoseBeforeBreakfastTitle, L10n.notificationGlucoseAfterBreakfast2hTitle:
            return .breakfast
        case L10n.notificationGlucoseBeforeLunchTitle, L10n.notificationGlucoseAfterLunch2hTitle:
            return .lunch
        case L10n.notificationGlucoseBeforeDinnerTitle, L10n.notificationGlucoseAfterDinner2hTitle:
            return .dinner
        default:
            return nil
        }
    }

    private static func decodeScheduledDate(from identifier: String) -> Date? {
        guard let range = identifier.range(of: #"d\d{8}\.\d{4}"#, options: .regularExpression) else {
            return nil
        }

        let token = identifier[range].dropFirst()
        let compact = String(token).replacingOccurrences(of: ".", with: "")
        guard compact.count == 12, compact.allSatisfy(\.isNumber) else { return nil }

        guard
            let year = Int(compact.prefix(4)),
            let month = Int(compact.dropFirst(4).prefix(2)),
            let day = Int(compact.dropFirst(6).prefix(2)),
            let hour = Int(compact.dropFirst(8).prefix(2)),
            let minute = Int(compact.dropFirst(10).prefix(2))
        else {
            return nil
        }

        var components = DateComponents()
        components.timeZone = Calendar.current.timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = 0
        return Calendar.current.date(from: components)
    }
}

struct NotificationActionContext: Sendable {
    let identifier: String
    let categoryIdentifier: String
    let title: String
    let body: String
    let mealSlotRawValue: String?
    let measurementTypeRawValue: String?
    let deliveredDate: Date?
}

/// Central notifications delegate that routes actions into MainActor use cases.
final class NotificationsCoordinator: NSObject, UNUserNotificationCenterDelegate {
    private let actionHandler: any NotificationsActionHandling
    private let quickEntryRouter: any NotificationQuickEntryRouting

    init(container: AppContainer) {
        self.actionHandler = container.notificationsActionUseCase
        self.quickEntryRouter = NotificationQuickEntryRouter.shared
        super.init()
    }

    init(
        actionHandler: any NotificationsActionHandling,
        quickEntryRouter: any NotificationQuickEntryRouting = NotificationQuickEntryRouter.shared
    ) {
        self.actionHandler = actionHandler
        self.quickEntryRouter = quickEntryRouter
        super.init()
    }

    // Present notifications while app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        guard let action = UserNotificationsRepository.parseAction(from: response) else {
            completionHandler()
            return
        }

        let content = response.notification.request.content
        let context = NotificationActionContext(
            identifier: response.notification.request.identifier,
            categoryIdentifier: content.categoryIdentifier,
            title: content.title,
            body: content.body,
            mealSlotRawValue: content.userInfo[UserNotificationsRepository.PayloadKeys.mealSlot] as? String,
            measurementTypeRawValue: content.userInfo[UserNotificationsRepository.PayloadKeys.measurementType] as? String,
            deliveredDate: response.notification.date
        )
        handleAction(action, context: context, completionHandler: completionHandler)
    }

    func handleAction(_ action: UserNotificationsRepository.HandledAction,
                      context: NotificationActionContext,
                      completionHandler: @escaping () -> Void) {
        Task { @MainActor [actionHandler, quickEntryRouter] in
            switch action {
            case .enter:
                quickEntryRouter.routeToQuickEntry(context: context)
            case .skip:
                await actionHandler.skip()
            case .snooze(let minutes):
                await actionHandler.snooze(
                    originalIdentifier: context.identifier,
                    minutes: minutes,
                    title: context.title,
                    body: context.body,
                    categoryIdentifier: context.categoryIdentifier
                )
            case .moveToLunch:
                await actionHandler.moveBeforeBreakfast(to: .lunch)
            case .moveToDinner:
                await actionHandler.moveBeforeBreakfast(to: .dinner)
            }
            completionHandler()
        }
    }
}
