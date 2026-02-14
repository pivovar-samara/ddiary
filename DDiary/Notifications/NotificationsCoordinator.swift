import Foundation
import UserNotifications

@MainActor
protocol NotificationsActionHandling: AnyObject {
    func skip() async
    func snooze(originalIdentifier: String, minutes: Int, title: String, body: String, categoryIdentifier: String) async
    func moveBeforeBreakfast(to meal: MealSlot) async
}

extension NotificationsActionUseCase: NotificationsActionHandling {}

struct NotificationActionContext: Sendable {
    let identifier: String
    let categoryIdentifier: String
    let title: String
    let body: String
}

/// Central notifications delegate that routes actions into MainActor use cases.
final class NotificationsCoordinator: NSObject, UNUserNotificationCenterDelegate {
    private let actionHandler: any NotificationsActionHandling

    init(container: AppContainer) {
        self.actionHandler = container.notificationsActionUseCase
        super.init()
    }

    init(actionHandler: any NotificationsActionHandling) {
        self.actionHandler = actionHandler
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
            body: content.body
        )
        handleAction(action, context: context, completionHandler: completionHandler)
    }

    func handleAction(_ action: UserNotificationsRepository.HandledAction,
                      context: NotificationActionContext,
                      completionHandler: @escaping () -> Void) {
        Task { @MainActor [actionHandler] in
            switch action {
            case .enter:
                // In v1, we rely on the app opening to the Today screen; further routing can be added later.
                break
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
