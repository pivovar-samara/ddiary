import Foundation
import UserNotifications

/// Central notifications delegate that routes actions into MainActor use cases.
final class NotificationsCoordinator: NSObject, UNUserNotificationCenterDelegate {
    private let container: AppContainer

    init(container: AppContainer) {
        self.container = container
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
        defer { completionHandler() }
        guard let action = UserNotificationsRepository.parseAction(from: response) else { return }

        let content = response.notification.request.content
        let id = response.notification.request.identifier
        let category = content.categoryIdentifier
        let title = content.title
        let body = content.body

        switch action {
        case .enter:
            // In v1, we rely on the app opening to the Today screen; further routing can be added later.
            break
        case .skip:
            Task { await self.container.notificationsActionUseCase.skip() }
        case .snooze(let minutes):
            Task {
                await self.container.notificationsActionUseCase.snooze(
                    originalIdentifier: id,
                    minutes: minutes,
                    title: title,
                    body: body,
                    categoryIdentifier: category
                )
            }
        case .moveToLunch:
            Task { await self.container.notificationsActionUseCase.moveBeforeBreakfast(to: .lunch) }
        case .moveToDinner:
            Task { await self.container.notificationsActionUseCase.moveBeforeBreakfast(to: .dinner) }
        }
    }
}
