import Foundation
import UserNotifications

struct UserNotificationsRepository: NotificationsRepository, Sendable {
    // MARK: - Identifiers
    enum IDs {
        // Categories
        static let bpCategory = "ddiary.bp.category"
        static let glucoseBeforeCategory = "ddiary.glucose.before.category"
        static let glucoseAfterCategory = "ddiary.glucose.after.category"
        static let glucoseBedtimeCategory = "ddiary.glucose.bedtime.category"

        // Actions
        static let enterAction = "ddiary.action.enter"
        static let skipAction = "ddiary.action.skip"
        static let snooze15Action = "ddiary.action.snooze.15"
        static let snooze30Action = "ddiary.action.snooze.30"
        static let snooze60Action = "ddiary.action.snooze.60"
        static let moveToLunchAction = "ddiary.action.move.lunch"
        static let moveToDinnerAction = "ddiary.action.move.dinner"

        // Prefixes
        static let bpPrefix = "ddiary.bp."
        static let glucoseBeforePrefix = "ddiary.glucose.before."
        static let glucoseAfterPrefix = "ddiary.glucose.after."
        static let glucoseBedtimePrefix = "ddiary.glucose.bedtime."
    }

    // MARK: - Public category registration
    static func registerCategories() {
        let enter = UNNotificationAction(identifier: IDs.enterAction, title: "Enter", options: [.foreground])
        let skip = UNNotificationAction(identifier: IDs.skipAction, title: "Skip", options: [])
        let snooze15 = UNNotificationAction(identifier: IDs.snooze15Action, title: "Snooze 15m", options: [])
        let snooze30 = UNNotificationAction(identifier: IDs.snooze30Action, title: "Snooze 30m", options: [])
        let snooze60 = UNNotificationAction(identifier: IDs.snooze60Action, title: "Snooze 60m", options: [])

        let moveToLunch = UNNotificationAction(identifier: IDs.moveToLunchAction, title: "Move to lunch", options: [])
        let moveToDinner = UNNotificationAction(identifier: IDs.moveToDinnerAction, title: "Move to dinner", options: [])

        let bpCategory = UNNotificationCategory(
            identifier: IDs.bpCategory,
            actions: [enter, snooze15, snooze30, snooze60, skip],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        let glucoseBeforeCategory = UNNotificationCategory(
            identifier: IDs.glucoseBeforeCategory,
            actions: [enter, moveToLunch, moveToDinner, snooze15, snooze30, snooze60, skip],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        let glucoseAfterCategory = UNNotificationCategory(
            identifier: IDs.glucoseAfterCategory,
            actions: [enter, snooze15, snooze30, snooze60, skip],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        let glucoseBedtimeCategory = UNNotificationCategory(
            identifier: IDs.glucoseBedtimeCategory,
            actions: [enter, snooze15, snooze30, snooze60, skip],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        let center = UNUserNotificationCenter.current()
        center.setNotificationCategories([bpCategory, glucoseBeforeCategory, glucoseAfterCategory, glucoseBedtimeCategory])
    }

    // MARK: - NotificationsRepository
    func requestAuthorization() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    func scheduleBloodPressure(times: [Int], activeWeekdays: Set<Int>) async throws {
        let center = UNUserNotificationCenter.current()
        for weekday in activeWeekdays.sorted() {
            for minutes in times {
                let hm = minutesToHourMinute(minutes)
                var comps = DateComponents()
                comps.weekday = weekday
                comps.hour = hm.hour
                comps.minute = hm.minute

                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
                let id = identifier(prefix: IDs.bpPrefix, components: comps, weekday: weekday)
                let content = makeContent(
                    title: "Blood Pressure",
                    body: "Time to measure your blood pressure.",
                    categoryIdentifier: IDs.bpCategory
                )
                let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
                await center.addOrReplace(request: request)
            }
        }
    }

    func cancelBloodPressure() async {
        await removeAll(withPrefixes: [IDs.bpPrefix])
    }

    func rescheduleBloodPressure(times: [Int], activeWeekdays: Set<Int>) async throws {
        await cancelBloodPressure()
        try await scheduleBloodPressure(times: times, activeWeekdays: activeWeekdays)
    }

    func scheduleGlucoseBeforeMeal(breakfast: DateComponents, lunch: DateComponents, dinner: DateComponents, isEnabled: Bool) async throws {
        guard isEnabled else { return }
        let center = UNUserNotificationCenter.current()
        let items: [(String, String, DateComponents)] = [
            ("Glucose — Before Breakfast", "Log glucose before breakfast.", breakfast),
            ("Glucose — Before Lunch", "Log glucose before lunch.", lunch),
            ("Glucose — Before Dinner", "Log glucose before dinner.", dinner)
        ]
        for (title, body, comps) in items {
            var dc = DateComponents()
            dc.hour = comps.hour
            dc.minute = comps.minute
            let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)
            let id = identifier(prefix: IDs.glucoseBeforePrefix, components: dc)
            let content = makeContent(title: title, body: body, categoryIdentifier: IDs.glucoseBeforeCategory)
            let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
            await center.addOrReplace(request: request)
        }
    }

    func scheduleGlucoseAfterMeal2h(breakfast: DateComponents, lunch: DateComponents, dinner: DateComponents, isEnabled: Bool) async throws {
        guard isEnabled else { return }
        let center = UNUserNotificationCenter.current()
        let items: [(String, String, DateComponents)] = [
            ("Glucose — After Breakfast (2h)", "Log glucose 2 hours after breakfast.", addingHours(breakfast, hours: 2)),
            ("Glucose — After Lunch (2h)", "Log glucose 2 hours after lunch.", addingHours(lunch, hours: 2)),
            ("Glucose — After Dinner (2h)", "Log glucose 2 hours after dinner.", addingHours(dinner, hours: 2))
        ]
        for (title, body, comps) in items {
            var dc = DateComponents()
            dc.hour = comps.hour
            dc.minute = comps.minute
            let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)
            let id = identifier(prefix: IDs.glucoseAfterPrefix, components: dc)
            let content = makeContent(title: title, body: body, categoryIdentifier: IDs.glucoseAfterCategory)
            let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
            await center.addOrReplace(request: request)
        }
    }

    func scheduleGlucoseBedtime(isEnabled: Bool, time: DateComponents?) async throws {
        guard isEnabled, let time else { return }
        let center = UNUserNotificationCenter.current()
        var dc = DateComponents()
        dc.hour = time.hour
        dc.minute = time.minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)
        let id = identifier(prefix: IDs.glucoseBedtimePrefix, components: dc)
        let content = makeContent(title: "Glucose — Bedtime", body: "Log bedtime glucose.", categoryIdentifier: IDs.glucoseBedtimeCategory)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        await center.addOrReplace(request: request)
    }

    func cancelGlucose() async {
        await removeAll(withPrefixes: [IDs.glucoseBeforePrefix, IDs.glucoseAfterPrefix, IDs.glucoseBedtimePrefix])
    }

    func rescheduleGlucose(
        breakfast: DateComponents,
        lunch: DateComponents,
        dinner: DateComponents,
        enableBeforeMeal: Bool,
        enableAfterMeal2h: Bool,
        enableBedtime: Bool,
        bedtimeTime: DateComponents?
    ) async throws {
        await cancelGlucose()
        try await scheduleGlucoseBeforeMeal(breakfast: breakfast, lunch: lunch, dinner: dinner, isEnabled: enableBeforeMeal)
        try await scheduleGlucoseAfterMeal2h(breakfast: breakfast, lunch: lunch, dinner: dinner, isEnabled: enableAfterMeal2h)
        try await scheduleGlucoseBedtime(isEnabled: enableBedtime, time: bedtimeTime)
    }

    func cancelAll() async {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    // MARK: - Handling helpers for App/Scene delegate
    enum HandledAction: Sendable {
        case enter
        case skip
        case snooze(minutes: Int)
        case moveToLunch
        case moveToDinner
    }

    static func parseAction(from response: UNNotificationResponse) -> HandledAction? {
        switch response.actionIdentifier {
        case IDs.enterAction: return .enter
        case IDs.skipAction: return .skip
        case IDs.snooze15Action: return .snooze(minutes: 15)
        case IDs.snooze30Action: return .snooze(minutes: 30)
        case IDs.snooze60Action: return .snooze(minutes: 60)
        case IDs.moveToLunchAction: return .moveToLunch
        case IDs.moveToDinnerAction: return .moveToDinner
        default: return nil
        }
    }

    // MARK: - Private helpers
    private func makeContent(title: String, body: String, categoryIdentifier: String, userInfo: [AnyHashable: Any] = [:]) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = categoryIdentifier
        if !userInfo.isEmpty { content.userInfo = userInfo }
        return content
    }

    private func minutesToHourMinute(_ minutes: Int) -> (hour: Int, minute: Int) {
        let hour = (minutes / 60) % 24
        let minute = minutes % 60
        return (hour, minute)
        
    }

    private func identifier(prefix: String, components: DateComponents, weekday: Int? = nil) -> String {
        let h = components.hour ?? 0
        let m = components.minute ?? 0
        if let w = weekday { return "\(prefix)w\(w).\(String(format: "%02d", h))\(String(format: "%02d", m))" }
        return "\(prefix)\(String(format: "%02d", h))\(String(format: "%02d", m))"
    }

    private func addingHours(_ components: DateComponents, hours: Int) -> DateComponents {
        var dc = DateComponents()
        let baseHour = components.hour ?? 0
        let newHour = (baseHour + hours) % 24
        dc.hour = newHour >= 0 ? newHour : (newHour + 24)
        dc.minute = components.minute ?? 0
        return dc
    }

    private func removeAll(withPrefixes prefixes: [String]) async {
        let center = UNUserNotificationCenter.current()
        let pendingIDs = await pendingRequests()
            .filter { id in prefixes.contains(where: { id.hasPrefix($0) }) }
        let deliveredIDs = await deliveredNotifications()
            .filter { id in prefixes.contains(where: { id.hasPrefix($0) }) }
        center.removePendingNotificationRequests(withIdentifiers: pendingIDs)
        center.removeDeliveredNotifications(withIdentifiers: deliveredIDs)
    }

    private func pendingRequests() async -> [String] {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
                let ids = requests.map { $0.identifier }
                continuation.resume(returning: ids)
            }
        }
    }

    private func deliveredNotifications() async -> [String] {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getDeliveredNotifications { notifications in
                let ids = notifications.map { $0.request.identifier }
                continuation.resume(returning: ids)
            }
        }
    }
}

// MARK: - UNUserNotificationCenter convenience
private extension UNUserNotificationCenter {
    func addOrReplace(request: UNNotificationRequest) async {
        // Remove any existing with the same identifier, then add.
        removePendingNotificationRequests(withIdentifiers: [request.identifier])
        await addAsync(request)
    }

    func addAsync(_ request: UNNotificationRequest) async {
        await withCheckedContinuation { continuation in
            add(request) { _ in
                continuation.resume()
            }
        }
    }
}

