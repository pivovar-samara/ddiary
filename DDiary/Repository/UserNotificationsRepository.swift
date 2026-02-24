import Foundation
import UserNotifications

struct PendingNotificationRecord: Sendable {
    let identifier: String
    let nextTriggerDate: Date?
    let categoryIdentifier: String
    let title: String
    let mealSlotRawValue: String?
    let measurementTypeRawValue: String?
}

struct DeliveredNotificationRecord: Sendable {
    let identifier: String
    let deliveredDate: Date
    let categoryIdentifier: String
    let title: String
    let mealSlotRawValue: String?
    let measurementTypeRawValue: String?
}

protocol UserNotificationCentering: Sendable {
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func setNotificationCategories(_ categories: Set<UNNotificationCategory>)
    func addOrReplace(request: UNNotificationRequest) async
    func removePendingNotificationRequests(withIdentifiers ids: [String])
    func removeDeliveredNotifications(withIdentifiers ids: [String])
    func removeAllPendingNotificationRequests()
    func removeAllDeliveredNotifications()
    func pendingRequestIdentifiers() async -> [String]
    func deliveredNotificationIdentifiers() async -> [String]
    func pendingNotificationRecords() async -> [PendingNotificationRecord]
    func deliveredNotificationRecords() async -> [DeliveredNotificationRecord]
}

struct LiveUserNotificationCenter: UserNotificationCentering, @unchecked Sendable {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            center.requestAuthorization(options: options) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {
        center.setNotificationCategories(categories)
    }

    func addOrReplace(request: UNNotificationRequest) async {
        center.removePendingNotificationRequests(withIdentifiers: [request.identifier])
        await withCheckedContinuation { continuation in
            center.add(request) { _ in
                continuation.resume()
            }
        }
    }

    func removePendingNotificationRequests(withIdentifiers ids: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    func removeDeliveredNotifications(withIdentifiers ids: [String]) {
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    func removeAllPendingNotificationRequests() {
        center.removeAllPendingNotificationRequests()
    }

    func removeAllDeliveredNotifications() {
        center.removeAllDeliveredNotifications()
    }

    func pendingRequestIdentifiers() async -> [String] {
        await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { requests in
                continuation.resume(returning: requests.map(\.identifier))
            }
        }
    }

    func deliveredNotificationIdentifiers() async -> [String] {
        await withCheckedContinuation { continuation in
            center.getDeliveredNotifications { notifications in
                continuation.resume(returning: notifications.map { $0.request.identifier })
            }
        }
    }

    func pendingNotificationRecords() async -> [PendingNotificationRecord] {
        await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { requests in
                let records = requests.map { request in
                    PendingNotificationRecord(
                        identifier: request.identifier,
                        nextTriggerDate: {
                            guard let calendarTrigger = request.trigger as? UNCalendarNotificationTrigger else { return nil }
                            return calendarTrigger.nextTriggerDate()
                        }(),
                        categoryIdentifier: request.content.categoryIdentifier,
                        title: request.content.title,
                        mealSlotRawValue: request.content.userInfo["mealSlot"] as? String,
                        measurementTypeRawValue: request.content.userInfo["measurementType"] as? String
                    )
                }
                continuation.resume(returning: records)
            }
        }
    }

    func deliveredNotificationRecords() async -> [DeliveredNotificationRecord] {
        await withCheckedContinuation { continuation in
            center.getDeliveredNotifications { notifications in
                let records = notifications.map { notification in
                    DeliveredNotificationRecord(
                        identifier: notification.request.identifier,
                        deliveredDate: notification.date,
                        categoryIdentifier: notification.request.content.categoryIdentifier,
                        title: notification.request.content.title,
                        mealSlotRawValue: notification.request.content.userInfo["mealSlot"] as? String,
                        measurementTypeRawValue: notification.request.content.userInfo["measurementType"] as? String
                    )
                }
                continuation.resume(returning: records)
            }
        }
    }
}

/*
Usage notes:

- Call `UserNotificationsRepository.registerCategories()` once at app launch to register notification categories.

- Call `NotificationsRepository.scheduleAllNotifications(settings:)` whenever notification settings change to schedule or reschedule notifications.

- Handle incoming notification responses in your App or Scene delegate's UNUserNotificationCenterDelegate method, e.g.:

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        if let action = UserNotificationsRepository.parseAction(from: response) {
            switch action {
            case .enter: /* handle enter action */
            case .skip: /* handle skip action */
            case .snooze(let minutes): /* handle snooze for given minutes */
            case .moveToLunch: /* handle move to lunch */
            case .moveToDinner: /* handle move to dinner */
            }
        }
        completionHandler()
    }

*/

struct UserNotificationsRepository: NotificationsRepository, Sendable {
    private let center: any UserNotificationCentering

    init(center: any UserNotificationCentering = LiveUserNotificationCenter()) {
        self.center = center
    }

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

    enum PayloadKeys {
        static let mealSlot = "mealSlot"
        static let measurementType = "measurementType"
    }

    // MARK: - Public category registration
    static func registerCategories(center: any UserNotificationCentering = LiveUserNotificationCenter()) {
        let enter = UNNotificationAction(identifier: IDs.enterAction, title: L10n.notificationActionEnter, options: [.foreground])
        let skip = UNNotificationAction(identifier: IDs.skipAction, title: L10n.notificationActionSkip, options: [])
        let snooze15 = UNNotificationAction(identifier: IDs.snooze15Action, title: L10n.notificationActionSnooze(15), options: [])
        let snooze30 = UNNotificationAction(identifier: IDs.snooze30Action, title: L10n.notificationActionSnooze(30), options: [])
        let snooze60 = UNNotificationAction(identifier: IDs.snooze60Action, title: L10n.notificationActionSnooze(60), options: [])

        let moveToLunch = UNNotificationAction(identifier: IDs.moveToLunchAction, title: L10n.notificationActionMoveToLunch, options: [])
        let moveToDinner = UNNotificationAction(identifier: IDs.moveToDinnerAction, title: L10n.notificationActionMoveToDinner, options: [])

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

        center.setNotificationCategories([bpCategory, glucoseBeforeCategory, glucoseAfterCategory, glucoseBedtimeCategory])
    }

    // MARK: - NotificationsRepository
    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func scheduleBloodPressure(times: [Int], activeWeekdays: Set<Int>) async throws {
        let normalizedWeekdays = Set(activeWeekdays.filter { (1...7).contains($0) })
        for weekday in normalizedWeekdays.sorted() {
            for minutes in times {
                let hm = minutesToHourMinute(minutes)
                var comps = DateComponents()
                comps.weekday = weekday
                comps.hour = hm.hour
                comps.minute = hm.minute

                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
                let id = identifier(prefix: IDs.bpPrefix, components: comps, weekday: weekday)
                let content = makeContent(
                    title: L10n.notificationBPTitle,
                    body: L10n.notificationBPBody,
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
        let items: [(String, String, DateComponents, MealSlot)] = [
            (L10n.notificationGlucoseBeforeBreakfastTitle, L10n.notificationGlucoseBeforeBreakfastBody, breakfast, .breakfast),
            (L10n.notificationGlucoseBeforeLunchTitle, L10n.notificationGlucoseBeforeLunchBody, lunch, .lunch),
            (L10n.notificationGlucoseBeforeDinnerTitle, L10n.notificationGlucoseBeforeDinnerBody, dinner, .dinner)
        ]
        for (title, body, comps, mealSlot) in items {
            var dc = DateComponents()
            dc.hour = comps.hour
            dc.minute = comps.minute
            let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)
            let id = identifier(prefix: IDs.glucoseBeforePrefix, components: dc)
            let content = makeContent(
                title: title,
                body: body,
                categoryIdentifier: IDs.glucoseBeforeCategory,
                userInfo: quickEntryUserInfo(mealSlot: mealSlot, measurementType: .beforeMeal)
            )
            let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
            await center.addOrReplace(request: request)
        }
    }

    func scheduleGlucoseAfterMeal2h(breakfast: DateComponents, lunch: DateComponents, dinner: DateComponents, isEnabled: Bool) async throws {
        guard isEnabled else { return }
        let items: [(String, String, DateComponents, MealSlot)] = [
            (L10n.notificationGlucoseAfterBreakfast2hTitle, L10n.notificationGlucoseAfterBreakfast2hBody, addingHours(breakfast, hours: 2), .breakfast),
            (L10n.notificationGlucoseAfterLunch2hTitle, L10n.notificationGlucoseAfterLunch2hBody, addingHours(lunch, hours: 2), .lunch),
            (L10n.notificationGlucoseAfterDinner2hTitle, L10n.notificationGlucoseAfterDinner2hBody, addingHours(dinner, hours: 2), .dinner)
        ]
        for (title, body, comps, mealSlot) in items {
            var dc = DateComponents()
            dc.hour = comps.hour
            dc.minute = comps.minute
            let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)
            let id = identifier(prefix: IDs.glucoseAfterPrefix, components: dc)
            let content = makeContent(
                title: title,
                body: body,
                categoryIdentifier: IDs.glucoseAfterCategory,
                userInfo: quickEntryUserInfo(mealSlot: mealSlot, measurementType: .afterMeal2h)
            )
            let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
            await center.addOrReplace(request: request)
        }
    }

    func scheduleGlucoseBedtime(isEnabled: Bool, time: DateComponents?) async throws {
        guard isEnabled, let time else { return }
        var dc = DateComponents()
        dc.hour = time.hour
        dc.minute = time.minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)
        let id = identifier(prefix: IDs.glucoseBedtimePrefix, components: dc)
        let content = makeContent(
            title: L10n.notificationGlucoseBedtimeTitle,
            body: L10n.notificationGlucoseBedtimeBody,
            categoryIdentifier: IDs.glucoseBedtimeCategory,
            userInfo: quickEntryUserInfo(mealSlot: .none, measurementType: .bedtime)
        )
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

    func rescheduleGlucoseCycle(
        configuration: GlucoseCycleConfiguration,
        startDate: Date,
        numberOfDays: Int
    ) async throws {
        await cancelGlucose()
        try await scheduleGlucoseCycle(
            configuration: configuration,
            startDate: startDate,
            numberOfDays: numberOfDays
        )
    }

    func cancelAll() async {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    // MARK: - One-off helpers (snooze / move / cancel by id)
    /// Schedule a one-off notification at the specified date with provided content.
    /// This does not repeat and is useful for snooze/move actions.
    public func scheduleOneOff(
        at date: Date,
        identifier: String,
        title: String,
        body: String,
        categoryIdentifier: String,
        userInfo: [AnyHashable: Any]
    ) async {
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let content = makeContent(
            title: title,
            body: body,
            categoryIdentifier: categoryIdentifier,
            userInfo: userInfo
        )
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        await center.addOrReplace(request: request)
    }

    /// Convenience for snoozing: schedules a one-off notification after N minutes.
    /// Does not cancel the original repeating reminder; it simply adds a one-time reminder.
    public func snooze(
        originalIdentifier: String,
        minutes: Int,
        title: String,
        body: String,
        categoryIdentifier: String
    ) async {
        let fireDate = Date().addingTimeInterval(TimeInterval(minutes * 60))
        let snoozedID = originalIdentifier + ".snooze.\(minutes)"
        await scheduleOneOff(
            at: fireDate,
            identifier: snoozedID,
            title: title,
            body: body,
            categoryIdentifier: categoryIdentifier,
            userInfo: [:]
        )
    }

    /// Cancel a specific notification by identifier (both pending and delivered).
    public func cancel(withIdentifier id: String) async {
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
    }

    public func cancelPlannedBloodPressureNotification(at scheduledDate: Date) async {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: scheduledDate)
        let components = calendar.dateComponents([.hour, .minute], from: scheduledDate)
        let repeatingID = identifier(prefix: IDs.bpPrefix, components: components, weekday: weekday)
        center.removeDeliveredNotifications(withIdentifiers: [repeatingID])
    }

    public func cancelPlannedGlucoseNotification(
        measurementType: GlucoseMeasurementType,
        at scheduledDate: Date
    ) async {
        let calendar = Calendar.current
        let prefix = glucosePrefix(for: measurementType)
        let components = calendar.dateComponents([.hour, .minute], from: scheduledDate)
        let repeatingID = identifier(prefix: prefix, components: components)
        let cycleID = cycleIdentifier(prefix: prefix, at: scheduledDate, calendar: calendar)

        let pendingIDs = Set(await center.pendingRequestIdentifiers())
        let deliveredIDs = Set(await center.deliveredNotificationIdentifiers())

        if pendingIDs.contains(cycleID) {
            center.removePendingNotificationRequests(withIdentifiers: [cycleID])
        }

        var deliveredToRemove: Set<String> = []
        if deliveredIDs.contains(cycleID) {
            deliveredToRemove.insert(cycleID)
        }
        if deliveredIDs.contains(repeatingID) {
            deliveredToRemove.insert(repeatingID)
        }
        if !deliveredToRemove.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: Array(deliveredToRemove))
        }
    }

    public func scheduledReminders(on day: Date) async -> [ScheduledReminder] {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: day)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        var reminders: [ScheduledReminder] = []

        let pending = await center.pendingNotificationRecords()
        for record in pending {
            guard let scheduledDate = record.nextTriggerDate else { continue }
            guard scheduledDate >= dayStart, scheduledDate < dayEnd else { continue }
            if let reminder = scheduledReminder(
                categoryIdentifier: record.categoryIdentifier,
                title: record.title,
                mealSlotRawValue: record.mealSlotRawValue,
                measurementTypeRawValue: record.measurementTypeRawValue,
                at: scheduledDate
            ) {
                reminders.append(reminder)
            }
        }

        let delivered = await center.deliveredNotificationRecords()
        for record in delivered {
            guard record.deliveredDate >= dayStart, record.deliveredDate < dayEnd else { continue }
            if let reminder = scheduledReminder(
                categoryIdentifier: record.categoryIdentifier,
                title: record.title,
                mealSlotRawValue: record.mealSlotRawValue,
                measurementTypeRawValue: record.measurementTypeRawValue,
                at: record.deliveredDate
            ) {
                reminders.append(reminder)
            }
        }

        return deduplicate(reminders: reminders, calendar: calendar)
            .sorted { $0.date < $1.date }
    }

    // MARK: - Handling helpers for App/Scene delegate

    /// Parses the action from a UNNotificationResponse.
    /// Use this inside your UNUserNotificationCenterDelegate's didReceive response method to handle actions.
    static func parseAction(from response: UNNotificationResponse) -> HandledAction? {
        parseAction(actionIdentifier: response.actionIdentifier)
    }

    static func parseAction(actionIdentifier: String) -> HandledAction? {
        switch actionIdentifier {
        case IDs.enterAction, UNNotificationDefaultActionIdentifier: return .enter
        case IDs.skipAction: return .skip
        case IDs.snooze15Action: return .snooze(minutes: 15)
        case IDs.snooze30Action: return .snooze(minutes: 30)
        case IDs.snooze60Action: return .snooze(minutes: 60)
        case IDs.moveToLunchAction: return .moveToLunch
        case IDs.moveToDinnerAction: return .moveToDinner
        default: return nil
        }
    }

    enum HandledAction: Sendable, Equatable {
        case enter
        case skip
        case snooze(minutes: Int)
        case moveToLunch
        case moveToDinner
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

    private func scheduleGlucoseCycle(
        configuration: GlucoseCycleConfiguration,
        startDate: Date,
        numberOfDays: Int
    ) async throws {
        guard numberOfDays > 0 else { return }
        let calendar = Calendar.current
        let startOfWindow = calendar.startOfDay(for: startDate)

        for dayOffset in 0..<numberOfDays {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: startOfWindow) else { continue }
            let reminders = GlucoseCyclePlanner.reminders(on: day, configuration: configuration, calendar: calendar)
                .filter { $0.date >= startDate }

            for reminder in reminders {
                let payload = cycleNotificationPayload(for: reminder)
                let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.date)
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                let request = UNNotificationRequest(
                    identifier: cycleIdentifier(prefix: payload.prefix, at: reminder.date, calendar: calendar),
                    content: makeContent(
                        title: payload.title,
                        body: payload.body,
                        categoryIdentifier: payload.categoryIdentifier,
                        userInfo: quickEntryUserInfo(
                            mealSlot: payload.mealSlot,
                            measurementType: payload.measurementType
                        )
                    ),
                    trigger: trigger
                )
                await center.addOrReplace(request: request)
            }
        }
    }

    private func cycleNotificationPayload(
        for reminder: GlucoseCycleReminder
    ) -> (
        title: String,
        body: String,
        categoryIdentifier: String,
        prefix: String,
        mealSlot: MealSlot,
        measurementType: GlucoseMeasurementType
    ) {
        switch (reminder.measurementType, reminder.mealSlot) {
        case (.beforeMeal, .breakfast):
            return (
                L10n.notificationGlucoseBeforeBreakfastTitle,
                L10n.notificationGlucoseBeforeBreakfastBody,
                IDs.glucoseBeforeCategory,
                IDs.glucoseBeforePrefix,
                .breakfast,
                .beforeMeal
            )
        case (.beforeMeal, .lunch):
            return (
                L10n.notificationGlucoseBeforeLunchTitle,
                L10n.notificationGlucoseBeforeLunchBody,
                IDs.glucoseBeforeCategory,
                IDs.glucoseBeforePrefix,
                .lunch,
                .beforeMeal
            )
        case (.beforeMeal, .dinner):
            return (
                L10n.notificationGlucoseBeforeDinnerTitle,
                L10n.notificationGlucoseBeforeDinnerBody,
                IDs.glucoseBeforeCategory,
                IDs.glucoseBeforePrefix,
                .dinner,
                .beforeMeal
            )
        case (.afterMeal2h, .breakfast):
            return (
                L10n.notificationGlucoseAfterBreakfast2hTitle,
                L10n.notificationGlucoseAfterBreakfast2hBody,
                IDs.glucoseAfterCategory,
                IDs.glucoseAfterPrefix,
                .breakfast,
                .afterMeal2h
            )
        case (.afterMeal2h, .lunch):
            return (
                L10n.notificationGlucoseAfterLunch2hTitle,
                L10n.notificationGlucoseAfterLunch2hBody,
                IDs.glucoseAfterCategory,
                IDs.glucoseAfterPrefix,
                .lunch,
                .afterMeal2h
            )
        case (.afterMeal2h, .dinner):
            return (
                L10n.notificationGlucoseAfterDinner2hTitle,
                L10n.notificationGlucoseAfterDinner2hBody,
                IDs.glucoseAfterCategory,
                IDs.glucoseAfterPrefix,
                .dinner,
                .afterMeal2h
            )
        case (.bedtime, _):
            return (
                L10n.notificationGlucoseBedtimeTitle,
                L10n.notificationGlucoseBedtimeBody,
                IDs.glucoseBedtimeCategory,
                IDs.glucoseBedtimePrefix,
                .none,
                .bedtime
            )
        default:
            return (
                L10n.notificationGlucoseBedtimeTitle,
                L10n.notificationGlucoseBedtimeBody,
                IDs.glucoseBedtimeCategory,
                IDs.glucoseBedtimePrefix,
                .none,
                .bedtime
            )
        }
    }

    private func quickEntryUserInfo(
        mealSlot: MealSlot,
        measurementType: GlucoseMeasurementType
    ) -> [AnyHashable: Any] {
        [
            PayloadKeys.mealSlot: mealSlot.rawValue,
            PayloadKeys.measurementType: measurementType.rawValue,
        ]
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

    private func cycleIdentifier(prefix: String, at date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let y = parts.year ?? 0
        let mo = parts.month ?? 0
        let d = parts.day ?? 0
        let h = parts.hour ?? 0
        let m = parts.minute ?? 0
        return "\(prefix)d\(String(format: "%04d", y))\(String(format: "%02d", mo))\(String(format: "%02d", d)).\(String(format: "%02d", h))\(String(format: "%02d", m))"
    }

    private func addingHours(_ components: DateComponents, hours: Int) -> DateComponents {
        var dc = DateComponents()
        let baseHour = components.hour ?? 0
        let newHour = (baseHour + hours) % 24
        dc.hour = newHour >= 0 ? newHour : (newHour + 24)
        dc.minute = components.minute ?? 0
        return dc
    }

    private func glucosePrefix(for measurementType: GlucoseMeasurementType) -> String {
        switch measurementType {
        case .beforeMeal:
            IDs.glucoseBeforePrefix
        case .afterMeal2h:
            IDs.glucoseAfterPrefix
        case .bedtime:
            IDs.glucoseBedtimePrefix
        }
    }

    private func scheduledReminder(
        categoryIdentifier: String,
        title: String,
        mealSlotRawValue: String?,
        measurementTypeRawValue: String?,
        at date: Date
    ) -> ScheduledReminder? {
        switch categoryIdentifier {
        case IDs.bpCategory:
            return ScheduledReminder(kind: .bloodPressure, date: date)
        case IDs.glucoseBedtimeCategory:
            return ScheduledReminder(kind: .glucose(mealSlot: .none, measurementType: .bedtime), date: date)
        case IDs.glucoseBeforeCategory, IDs.glucoseAfterCategory:
            let measurementType: GlucoseMeasurementType
            if let raw = measurementTypeRawValue, let parsed = GlucoseMeasurementType(rawValue: raw) {
                measurementType = parsed
            } else {
                measurementType = (categoryIdentifier == IDs.glucoseBeforeCategory) ? .beforeMeal : .afterMeal2h
            }

            guard let mealSlot = resolveMealSlot(rawValue: mealSlotRawValue, title: title) else { return nil }
            return ScheduledReminder(
                kind: .glucose(mealSlot: mealSlot, measurementType: measurementType),
                date: date
            )
        default:
            return nil
        }
    }

    private func resolveMealSlot(rawValue: String?, title: String) -> MealSlot? {
        if let rawValue, let slot = MealSlot(rawValue: rawValue) {
            return slot
        }

        switch title {
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

    private func deduplicate(reminders: [ScheduledReminder], calendar: Calendar) -> [ScheduledReminder] {
        struct ReminderKey: Hashable {
            let kind: String
            let mealSlot: String
            let measurementType: String
            let year: Int
            let month: Int
            let day: Int
            let hour: Int
            let minute: Int
        }

        var unique: [ReminderKey: ScheduledReminder] = [:]
        for reminder in reminders {
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.date)
            let (kind, mealSlot, measurementType): (String, String, String) = {
                switch reminder.kind {
                case .bloodPressure:
                    return ("bp", "none", "none")
                case .glucose(let mealSlot, let measurementType):
                    return ("glucose", mealSlot.rawValue, measurementType.rawValue)
                }
            }()
            let key = ReminderKey(
                kind: kind,
                mealSlot: mealSlot,
                measurementType: measurementType,
                year: components.year ?? 0,
                month: components.month ?? 0,
                day: components.day ?? 0,
                hour: components.hour ?? 0,
                minute: components.minute ?? 0
            )
            let existing = unique[key]
            if existing == nil || reminder.date < (existing?.date ?? reminder.date) {
                unique[key] = reminder
            }
        }
        return Array(unique.values)
    }

    private func removeAll(withPrefixes prefixes: [String]) async {
        let pendingIDs = await center.pendingRequestIdentifiers()
            .filter { id in prefixes.contains(where: { id.hasPrefix($0) }) }
        let deliveredIDs = await center.deliveredNotificationIdentifiers()
            .filter { id in prefixes.contains(where: { id.hasPrefix($0) }) }
        center.removePendingNotificationRequests(withIdentifiers: pendingIDs)
        center.removeDeliveredNotifications(withIdentifiers: deliveredIDs)
    }
}

private func nextDate(matching components: DateComponents, from base: Date = Date(), calendar: Calendar = .current) -> Date? {
    var comps = DateComponents()
    comps.hour = components.hour
    comps.minute = components.minute
    return calendar.nextDate(after: base, matching: comps, matchingPolicy: .nextTime, direction: .forward)
}
