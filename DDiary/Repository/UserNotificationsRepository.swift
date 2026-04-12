import Foundation
import UserNotifications

struct PendingNotificationRecord: Sendable {
    let identifier: String
    let nextTriggerDate: Date?
    let categoryIdentifier: String
    let title: String
    let body: String
    let soundName: String?
    let userInfoStrings: [String: String]
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
    func addOrReplace(request: UNNotificationRequest) async -> Bool
    func removePendingNotificationRequests(withIdentifiers ids: [String])
    func removeDeliveredNotifications(withIdentifiers ids: [String])
    func removeAllPendingNotificationRequests()
    func removeAllDeliveredNotifications()
    func pendingRequestIdentifiers() async -> [String]
    func deliveredNotificationIdentifiers() async -> [String]
    func pendingNotificationRecords() async -> [PendingNotificationRecord]
    func deliveredNotificationRecords() async -> [DeliveredNotificationRecord]
    func setBadgeCount(_ count: Int) async
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

    func addOrReplace(request: UNNotificationRequest) async -> Bool {
        center.removePendingNotificationRequests(withIdentifiers: [request.identifier])
        return await withCheckedContinuation { continuation in
            center.add(request) { error in
                continuation.resume(returning: error == nil)
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
                    let userInfoStrings = request.content.userInfo.reduce(into: [String: String]()) { dict, pair in
                        if let key = pair.key as? String, let value = pair.value as? String {
                            dict[key] = value
                        }
                    }
                    return PendingNotificationRecord(
                        identifier: request.identifier,
                        nextTriggerDate: {
                            guard let calendarTrigger = request.trigger as? UNCalendarNotificationTrigger else { return nil }
                            return calendarTrigger.nextTriggerDate()
                        }(),
                        categoryIdentifier: request.content.categoryIdentifier,
                        title: request.content.title,
                        body: request.content.body,
                        soundName: (request.content.sound).map { _ in "alarm-tone.caf" },
                        userInfoStrings: userInfoStrings,
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

    func setBadgeCount(_ count: Int) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            center.setBadgeCount(count) { _ in continuation.resume() }
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
            }
        }
        completionHandler()
    }

*/

struct UserNotificationsRepository: NotificationsRepository, Sendable {
    private static let maxPendingNotificationRequests = 64
    private let center: any UserNotificationCentering
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private let schedulingWindowDays: Int

    init(
        center: any UserNotificationCentering = LiveUserNotificationCenter(),
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = Date.init,
        schedulingWindowDays: Int = 28
    ) {
        self.center = center
        self.calendar = calendar
        self.now = now
        self.schedulingWindowDays = max(1, schedulingWindowDays)
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

        let bpCategory = UNNotificationCategory(
            identifier: IDs.bpCategory,
            actions: [enter, snooze15, snooze30, snooze60, skip],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        let glucoseBeforeCategory = UNNotificationCategory(
            identifier: IDs.glucoseBeforeCategory,
            actions: [enter, snooze15, snooze30, snooze60, skip],
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

    func hasPendingNotificationRequests() async -> Bool {
        let pendingIDs = await center.pendingRequestIdentifiers()
        return pendingIDs.contains(where: shouldPreservePendingRequestOnStartup)
    }

    func scheduleBloodPressure(times: [Int], activeWeekdays: Set<Int>) async throws {
        let normalizedWeekdays = Set(activeWeekdays.filter { (1...7).contains($0) })
        let normalizedTimes = Array(Set(times))
        guard !normalizedWeekdays.isEmpty, !normalizedTimes.isEmpty else { return }
        let windowDays = await effectiveWindowDays(
            remindersPerDay: normalizedTimes.count,
            requestedWindowDays: nil
        )
        guard windowDays > 0 else { return }

        let baseNow = now()
        for day in upcomingSchedulingDays(from: baseNow, windowDays: windowDays) {
            let weekday = calendar.component(.weekday, from: day)
            guard normalizedWeekdays.contains(weekday) else { continue }
            for minutes in normalizedTimes {
                let hm = minutesToHourMinute(minutes)
                let fireDate = scheduleDate(on: day, hour: hm.hour, minute: hm.minute)
                guard let fireDate, fireDate > baseNow else { continue }

                let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                let id = cycleIdentifier(prefix: IDs.bpPrefix, at: fireDate, calendar: calendar)
                let content = makeContent(
                    title: L10n.notificationBPTitle,
                    body: L10n.notificationBPBody,
                    categoryIdentifier: IDs.bpCategory
                )
                let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
                _ = await center.addOrReplace(request: request)
            }
        }
    }

    func cancelBloodPressure() async {
        await removeAll(withPrefixes: [IDs.bpPrefix])
    }

    func rescheduleBloodPressure(times: [Int], activeWeekdays: Set<Int>) async throws {
        await removeAll(withPrefixes: [IDs.bpPrefix], preservingOneOff: true)
        try await scheduleBloodPressure(times: times, activeWeekdays: activeWeekdays)
    }

    func scheduleGlucoseBeforeMeal(breakfast: DateComponents, lunch: DateComponents, dinner: DateComponents, isEnabled: Bool) async throws {
        try await scheduleGlucoseBeforeMeal(
            breakfast: breakfast,
            lunch: lunch,
            dinner: dinner,
            isEnabled: isEnabled,
            windowDaysOverride: nil
        )
    }

    func scheduleGlucoseAfterMeal2h(breakfast: DateComponents, lunch: DateComponents, dinner: DateComponents, isEnabled: Bool) async throws {
        try await scheduleGlucoseAfterMeal2h(
            breakfast: breakfast,
            lunch: lunch,
            dinner: dinner,
            isEnabled: isEnabled,
            windowDaysOverride: nil
        )
    }

    func scheduleGlucoseBedtime(isEnabled: Bool, time: DateComponents?) async throws {
        try await scheduleGlucoseBedtime(
            isEnabled: isEnabled,
            time: time,
            windowDaysOverride: nil
        )
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
        bedtimeTime: DateComponents?
    ) async throws {
        await removeAll(
            withPrefixes: [IDs.glucoseBeforePrefix, IDs.glucoseAfterPrefix, IDs.glucoseBedtimePrefix],
            preservingOneOff: true
        )
        let bedtimeEnabled = bedtimeTime != nil
        let remindersPerDay =
            (enableBeforeMeal ? 3 : 0)
            + (enableAfterMeal2h ? 3 : 0)
            + (bedtimeEnabled ? 1 : 0)
        let windowDays = await effectiveWindowDays(
            remindersPerDay: remindersPerDay,
            requestedWindowDays: nil
        )
        guard windowDays > 0 else { return }
        try await scheduleGlucoseBeforeMeal(
            breakfast: breakfast,
            lunch: lunch,
            dinner: dinner,
            isEnabled: enableBeforeMeal,
            windowDaysOverride: windowDays
        )
        try await scheduleGlucoseAfterMeal2h(
            breakfast: breakfast,
            lunch: lunch,
            dinner: dinner,
            isEnabled: enableAfterMeal2h,
            windowDaysOverride: windowDays
        )
        try await scheduleGlucoseBedtime(
            isEnabled: bedtimeEnabled,
            time: bedtimeTime,
            windowDaysOverride: windowDays
        )
    }

    func rescheduleGlucoseCycle(
        configuration: GlucoseCycleConfiguration,
        startDate: Date,
        numberOfDays: Int
    ) async throws {
        await removeAll(
            withPrefixes: [IDs.glucoseBeforePrefix, IDs.glucoseAfterPrefix, IDs.glucoseBedtimePrefix],
            preservingOneOff: true
        )
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

    func setBadgeCount(_ count: Int) async {
        await center.setBadgeCount(count)
    }

    func updateBadgesAfterScheduling() async {
        let records = await center.pendingNotificationRecords()
        let sorted = records
            .filter { !shouldPreservePendingRequestOnStartup($0.identifier) }
            .sorted { ($0.nextTriggerDate ?? .distantFuture) < ($1.nextTriggerDate ?? .distantFuture) }

        for (index, record) in sorted.enumerated() {
            guard let fireDate = record.nextTriggerDate else { continue }
            let content = UNMutableNotificationContent()
            content.title = record.title
            content.body = record.body
            if let soundName = record.soundName {
                content.sound = UNNotificationSound(named: UNNotificationSoundName(soundName))
            }
            content.categoryIdentifier = record.categoryIdentifier
            if !record.userInfoStrings.isEmpty {
                content.userInfo = Dictionary(uniqueKeysWithValues: record.userInfoStrings.map { ($0.key as AnyHashable, $0.value) })
            }
            content.badge = NSNumber(value: index + 1)
            let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(identifier: record.identifier, content: content, trigger: trigger)
            _ = await center.addOrReplace(request: request)
        }
    }

    func cancelAllExceptOneOffRequests() async {
        let allPendingIDs = await center.pendingRequestIdentifiers()
        let toRemove = allPendingIDs.filter { !shouldPreservePendingRequestOnStartup($0) }
        center.removePendingNotificationRequests(withIdentifiers: toRemove)
        center.removeAllDeliveredNotifications()
    }

    // MARK: - One-off helpers (snooze / cancel by id)
    /// Schedule a one-off notification at the specified date with provided content.
    /// This does not repeat and is useful for action-driven follow-up reminders.
    public func scheduleOneOff(
        at date: Date,
        identifier: String,
        title: String,
        body: String,
        categoryIdentifier: String,
        userInfo: [AnyHashable: Any]
    ) async {
        await reservePendingCapacityForOneOff(excluding: identifier)
        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let content = makeContent(
            title: title,
            body: body,
            categoryIdentifier: categoryIdentifier,
            userInfo: userInfo
        )
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        let scheduled = await center.addOrReplace(request: request)
        guard !scheduled else { return }

        // Recover from transient add failures (typically 64-pending cap races) by freeing one slot and retrying once.
        await reservePendingCapacityForOneOff(excluding: identifier)
        _ = await center.addOrReplace(request: request)
    }

    /// Convenience for snoozing: schedules a one-off notification after N minutes.
    /// Does not cancel the original planned reminder; it simply adds a one-time reminder.
    public func snooze(
        originalIdentifier: String,
        minutes: Int,
        title: String,
        body: String,
        categoryIdentifier: String,
        mealSlotRawValue: String?,
        measurementTypeRawValue: String?
    ) async {
        let fireDate = now().addingTimeInterval(TimeInterval(minutes * 60))
        let snoozedID = originalIdentifier + ".snooze.\(minutes)"
        var userInfo: [AnyHashable: Any] = [:]
        if let mealSlotRawValue {
            userInfo[PayloadKeys.mealSlot] = mealSlotRawValue
        }
        if let measurementTypeRawValue {
            userInfo[PayloadKeys.measurementType] = measurementTypeRawValue
        }
        await scheduleOneOff(
            at: fireDate,
            identifier: snoozedID,
            title: title,
            body: body,
            categoryIdentifier: categoryIdentifier,
            userInfo: userInfo
        )
    }

    /// Cancel a specific notification by identifier (both pending and delivered).
    public func cancel(withIdentifier id: String) async {
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
    }

    public func cancelPlannedBloodPressureNotification(at scheduledDate: Date) async {
        let calendar = self.calendar
        let weekday = calendar.component(.weekday, from: scheduledDate)
        let components = calendar.dateComponents([.hour, .minute], from: scheduledDate)
        let repeatingID = identifier(prefix: IDs.bpPrefix, components: components, weekday: weekday)
        let dayID = cycleIdentifier(prefix: IDs.bpPrefix, at: scheduledDate, calendar: calendar)
        let ids = [repeatingID, dayID]
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    public func cancelPlannedGlucoseNotification(
        measurementType: GlucoseMeasurementType,
        at scheduledDate: Date
    ) async {
        let calendar = self.calendar
        let prefix = glucosePrefix(for: measurementType)
        let components = calendar.dateComponents([.hour, .minute], from: scheduledDate)
        let repeatingID = identifier(prefix: prefix, components: components)
        let cycleID = cycleIdentifier(prefix: prefix, at: scheduledDate, calendar: calendar)

        let pendingIDs = Set(await center.pendingRequestIdentifiers())
        let deliveredIDs = Set(await center.deliveredNotificationIdentifiers())

        let candidateIDs = Set([cycleID, repeatingID])
        let pendingToRemove = pendingIDs.intersection(candidateIDs)
        if !pendingToRemove.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: Array(pendingToRemove))
        }

        let deliveredToRemove = deliveredIDs.intersection(candidateIDs)
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
        default: return nil
        }
    }

    enum HandledAction: Sendable, Equatable {
        case enter
        case skip
        case snooze(minutes: Int)
    }

    // MARK: - Private helpers
    private func makeContent(title: String, body: String, categoryIdentifier: String, userInfo: [AnyHashable: Any] = [:]) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = UNNotificationSound(named: UNNotificationSoundName("alarm-tone.caf"))
        content.categoryIdentifier = categoryIdentifier
        if !userInfo.isEmpty { content.userInfo = userInfo }
        return content
    }

    private func scheduleGlucoseCycle(
        configuration: GlucoseCycleConfiguration,
        startDate: Date,
        numberOfDays: Int
    ) async throws {
        let cappedDays = await effectiveWindowDays(
            remindersPerDay: 2,
            requestedWindowDays: numberOfDays
        )
        guard cappedDays > 0 else { return }
        let calendar = Calendar.current
        let startOfWindow = calendar.startOfDay(for: startDate)

        for dayOffset in 0..<cappedDays {
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
                _ = await center.addOrReplace(request: request)
            }
        }
    }

    private func scheduleGlucoseBeforeMeal(
        breakfast: DateComponents,
        lunch: DateComponents,
        dinner: DateComponents,
        isEnabled: Bool,
        windowDaysOverride: Int?
    ) async throws {
        guard isEnabled else { return }
        let items: [(String, String, Int, Int, MealSlot)] = [
            (
                L10n.notificationGlucoseBeforeBreakfastTitle,
                L10n.notificationGlucoseBeforeBreakfastBody,
                breakfast.hour ?? 0,
                breakfast.minute ?? 0,
                .breakfast
            ),
            (
                L10n.notificationGlucoseBeforeLunchTitle,
                L10n.notificationGlucoseBeforeLunchBody,
                lunch.hour ?? 0,
                lunch.minute ?? 0,
                .lunch
            ),
            (
                L10n.notificationGlucoseBeforeDinnerTitle,
                L10n.notificationGlucoseBeforeDinnerBody,
                dinner.hour ?? 0,
                dinner.minute ?? 0,
                .dinner
            )
        ]

        let windowDays = await effectiveWindowDays(
            remindersPerDay: items.count,
            requestedWindowDays: windowDaysOverride
        )
        guard windowDays > 0 else { return }

        let baseNow = now()
        for day in upcomingSchedulingDays(from: baseNow, windowDays: windowDays) {
            for (title, body, hour, minute, mealSlot) in items {
                guard let fireDate = scheduleDate(on: day, hour: hour, minute: minute), fireDate > baseNow else { continue }
                let dc = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
                let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: false)
                let id = cycleIdentifier(prefix: IDs.glucoseBeforePrefix, at: fireDate, calendar: calendar)
                let content = makeContent(
                    title: title,
                    body: body,
                    categoryIdentifier: IDs.glucoseBeforeCategory,
                    userInfo: quickEntryUserInfo(mealSlot: mealSlot, measurementType: .beforeMeal)
                )
                let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
                _ = await center.addOrReplace(request: request)
            }
        }
    }

    private func scheduleGlucoseAfterMeal2h(
        breakfast: DateComponents,
        lunch: DateComponents,
        dinner: DateComponents,
        isEnabled: Bool,
        windowDaysOverride: Int?
    ) async throws {
        guard isEnabled else { return }
        let items: [(String, String, Int, Int, MealSlot)] = [
            (
                L10n.notificationGlucoseAfterBreakfast2hTitle,
                L10n.notificationGlucoseAfterBreakfast2hBody,
                breakfast.hour ?? 0,
                breakfast.minute ?? 0,
                .breakfast
            ),
            (
                L10n.notificationGlucoseAfterLunch2hTitle,
                L10n.notificationGlucoseAfterLunch2hBody,
                lunch.hour ?? 0,
                lunch.minute ?? 0,
                .lunch
            ),
            (
                L10n.notificationGlucoseAfterDinner2hTitle,
                L10n.notificationGlucoseAfterDinner2hBody,
                dinner.hour ?? 0,
                dinner.minute ?? 0,
                .dinner
            )
        ]

        let windowDays = await effectiveWindowDays(
            remindersPerDay: items.count,
            requestedWindowDays: windowDaysOverride
        )
        guard windowDays > 0 else { return }

        let baseNow = now()
        for day in upcomingSchedulingDays(from: baseNow, windowDays: windowDays) {
            for (title, body, baseHour, baseMinute, mealSlot) in items {
                guard let mealDate = scheduleDate(on: day, hour: baseHour, minute: baseMinute) else { continue }
                guard let fireDate = calendar.date(byAdding: .hour, value: 2, to: mealDate), fireDate > baseNow else { continue }

                let dc = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
                let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: false)
                let id = cycleIdentifier(prefix: IDs.glucoseAfterPrefix, at: fireDate, calendar: calendar)
                let content = makeContent(
                    title: title,
                    body: body,
                    categoryIdentifier: IDs.glucoseAfterCategory,
                    userInfo: quickEntryUserInfo(mealSlot: mealSlot, measurementType: .afterMeal2h)
                )
                let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
                _ = await center.addOrReplace(request: request)
            }
        }
    }

    private func scheduleGlucoseBedtime(
        isEnabled: Bool,
        time: DateComponents?,
        windowDaysOverride: Int?
    ) async throws {
        guard isEnabled, let time else { return }
        let windowDays = await effectiveWindowDays(
            remindersPerDay: 1,
            requestedWindowDays: windowDaysOverride
        )
        guard windowDays > 0 else { return }

        let baseNow = now()
        for day in upcomingSchedulingDays(from: baseNow, windowDays: windowDays) {
            guard
                let fireDate = scheduleDate(on: day, hour: time.hour ?? 0, minute: time.minute ?? 0),
                fireDate > baseNow
            else { continue }
            let dc = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: false)
            let id = cycleIdentifier(prefix: IDs.glucoseBedtimePrefix, at: fireDate, calendar: calendar)
            let content = makeContent(
                title: L10n.notificationGlucoseBedtimeTitle,
                body: L10n.notificationGlucoseBedtimeBody,
                categoryIdentifier: IDs.glucoseBedtimeCategory,
                userInfo: quickEntryUserInfo(mealSlot: .none, measurementType: .bedtime)
            )
            let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
            _ = await center.addOrReplace(request: request)
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

    private func upcomingSchedulingDays(from referenceDate: Date, windowDays: Int) -> [Date] {
        guard windowDays > 0 else { return [] }
        let startDay = calendar.startOfDay(for: referenceDate)
        return (0..<windowDays).compactMap { dayOffset in
            calendar.date(byAdding: .day, value: dayOffset, to: startDay)
        }
    }

    private func effectiveWindowDays(
        remindersPerDay: Int,
        requestedWindowDays: Int?
    ) async -> Int {
        guard remindersPerDay > 0 else { return 0 }
        let requestedDays = max(0, min(schedulingWindowDays, requestedWindowDays ?? schedulingWindowDays))
        guard requestedDays > 0 else { return 0 }

        let capacity = await remainingPendingRequestCapacity()
        guard capacity > 0 else { return 0 }

        let cappedByCapacity = capacity / remindersPerDay
        guard cappedByCapacity > 0 else { return 0 }
        return min(requestedDays, cappedByCapacity)
    }

    private func remainingPendingRequestCapacity() async -> Int {
        let currentPending = await center.pendingRequestIdentifiers().count
        return max(0, Self.maxPendingNotificationRequests - currentPending)
    }

    private func reservePendingCapacityForOneOff(excluding identifier: String) async {
        let pending = await center.pendingNotificationRecords()
        guard pending.count >= Self.maxPendingNotificationRequests else { return }

        let evictionCandidate = pending
            .filter { $0.identifier != identifier }
            .max { lhs, rhs in
                (lhs.nextTriggerDate ?? .distantFuture) < (rhs.nextTriggerDate ?? .distantFuture)
            }

        guard let evictionCandidate else { return }
        center.removePendingNotificationRequests(withIdentifiers: [evictionCandidate.identifier])
    }

    private func scheduleDate(on day: Date, hour: Int, minute: Int) -> Date? {
        var comps = calendar.dateComponents([.year, .month, .day], from: day)
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        return calendar.date(from: comps)
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

    private func shouldPreservePendingRequestOnStartup(_ identifier: String) -> Bool {
        identifier.contains(".snooze.") || identifier.contains(".shifted.")
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

    private func removeAll(withPrefixes prefixes: [String], preservingOneOff: Bool = false) async {
        let pendingIDs = await center.pendingRequestIdentifiers()
            .filter { id in
                prefixes.contains(where: { id.hasPrefix($0) })
                    && !(preservingOneOff && shouldPreservePendingRequestOnStartup(id))
            }
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
