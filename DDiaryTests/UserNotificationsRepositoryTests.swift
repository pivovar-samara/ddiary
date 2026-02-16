import XCTest
import UserNotifications
@testable import DDiary

@MainActor
final class UserNotificationsRepositoryTests: XCTestCase {
    func test_registerCategories_setsAllExpectedCategories() {
        let center = FakeNotificationCenter()

        UserNotificationsRepository.registerCategories(center: center)

        let identifiers = Set(center.categories.map(\.identifier))
        XCTAssertEqual(identifiers, Set([
            UserNotificationsRepository.IDs.bpCategory,
            UserNotificationsRepository.IDs.glucoseBeforeCategory,
            UserNotificationsRepository.IDs.glucoseAfterCategory,
            UserNotificationsRepository.IDs.glucoseBedtimeCategory
        ]))
    }

    func test_scheduleBloodPressure_createsRequestsForEachWeekdayAndTime() async throws {
        let center = FakeNotificationCenter()
        let repository = UserNotificationsRepository(center: center)

        try await repository.scheduleBloodPressure(times: [540, 1260], activeWeekdays: [2, 4])

        let ids = Set(center.pendingRequests.keys)
        XCTAssertEqual(ids, Set([
            "ddiary.bp.w2.0900",
            "ddiary.bp.w2.2100",
            "ddiary.bp.w4.0900",
            "ddiary.bp.w4.2100"
        ]))
        XCTAssertEqual(center.pendingRequests.count, 4)

        let request = try XCTUnwrap(center.pendingRequests["ddiary.bp.w2.0900"])
        XCTAssertEqual(request.content.categoryIdentifier, UserNotificationsRepository.IDs.bpCategory)
        XCTAssertEqual(request.content.title, L10n.notificationBPTitle)
        let trigger = try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)
        XCTAssertTrue(trigger.repeats)
        XCTAssertEqual(trigger.dateComponents.weekday, 2)
        XCTAssertEqual(trigger.dateComponents.hour, 9)
        XCTAssertEqual(trigger.dateComponents.minute, 0)
    }

    func test_rescheduleGlucose_removesExistingPrefixedRequestsAndSchedulesEnabledKindsOnly() async throws {
        let center = FakeNotificationCenter()
        let repository = UserNotificationsRepository(center: center)

        center.pendingRequests["ddiary.glucose.before.0800"] = makeRequest(id: "ddiary.glucose.before.0800")
        center.pendingRequests["ddiary.glucose.after.1000"] = makeRequest(id: "ddiary.glucose.after.1000")
        center.pendingRequests["ddiary.glucose.bedtime.2200"] = makeRequest(id: "ddiary.glucose.bedtime.2200")
        center.pendingRequests["ddiary.bp.w2.0900"] = makeRequest(id: "ddiary.bp.w2.0900")
        center.deliveredIdentifiers = [
            "ddiary.glucose.before.0800",
            "ddiary.glucose.after.1000",
            "ddiary.glucose.bedtime.2200",
            "ddiary.bp.w2.0900"
        ]

        try await repository.rescheduleGlucose(
            breakfast: DateComponents(hour: 8, minute: 0),
            lunch: DateComponents(hour: 13, minute: 0),
            dinner: DateComponents(hour: 19, minute: 0),
            enableBeforeMeal: true,
            enableAfterMeal2h: false,
            enableBedtime: true,
            bedtimeTime: DateComponents(hour: 22, minute: 15)
        )

        XCTAssertNotNil(center.pendingRequests["ddiary.bp.w2.0900"])
        XCTAssertNotNil(center.pendingRequests["ddiary.glucose.before.0800"])
        XCTAssertNotNil(center.pendingRequests["ddiary.glucose.before.1300"])
        XCTAssertNotNil(center.pendingRequests["ddiary.glucose.before.1900"])
        XCTAssertNotNil(center.pendingRequests["ddiary.glucose.bedtime.2215"])
        XCTAssertNil(center.pendingRequests["ddiary.glucose.after.1000"])
        XCTAssertNil(center.pendingRequests["ddiary.glucose.after.1500"])
        XCTAssertNil(center.pendingRequests["ddiary.glucose.after.2100"])

        let removedPending = Set(center.removedPendingIdentifiers.flatMap { $0 })
        XCTAssertTrue(removedPending.contains("ddiary.glucose.before.0800"))
        XCTAssertTrue(removedPending.contains("ddiary.glucose.after.1000"))
        XCTAssertTrue(removedPending.contains("ddiary.glucose.bedtime.2200"))

        let removedDelivered = Set(center.removedDeliveredIdentifiers.flatMap { $0 })
        XCTAssertTrue(removedDelivered.contains("ddiary.glucose.before.0800"))
        XCTAssertTrue(removedDelivered.contains("ddiary.glucose.after.1000"))
        XCTAssertTrue(removedDelivered.contains("ddiary.glucose.bedtime.2200"))
    }

    func test_requestAuthorization_passthroughError() async {
        let center = FakeNotificationCenter()
        center.authorizationResult = .failure(TestError.forced)
        let repository = UserNotificationsRepository(center: center)

        do {
            _ = try await repository.requestAuthorization()
            XCTFail("Expected requestAuthorization to throw")
        } catch {
            // expected
        }
    }

    func test_rescheduleGlucoseCycle_schedulesOnlyCycleRemindersForWindow() async throws {
        let center = FakeNotificationCenter()
        let repository = UserNotificationsRepository(center: center)
        let calendar = Calendar.current
        let startDate = calendar.date(from: DateComponents(year: 2026, month: 2, day: 16, hour: 7, minute: 30)) ?? Date()

        let configuration = GlucoseCycleConfiguration(
            anchorDate: calendar.startOfDay(for: startDate),
            breakfast: DateComponents(hour: 8, minute: 0),
            lunch: DateComponents(hour: 13, minute: 0),
            dinner: DateComponents(hour: 19, minute: 0),
            bedtime: DateComponents(hour: 22, minute: 15)
        )

        try await repository.rescheduleGlucoseCycle(
            configuration: configuration,
            startDate: startDate,
            numberOfDays: 4
        )

        let day1 = calendar.startOfDay(for: startDate)
        let day2 = calendar.date(byAdding: .day, value: 1, to: day1) ?? day1
        let day3 = calendar.date(byAdding: .day, value: 2, to: day1) ?? day1
        let day4 = calendar.date(byAdding: .day, value: 3, to: day1) ?? day1

        let expected = Set([
            cycleID(prefix: UserNotificationsRepository.IDs.glucoseBeforePrefix, day: day1, hour: 8, minute: 0, calendar: calendar),
            cycleID(prefix: UserNotificationsRepository.IDs.glucoseAfterPrefix, day: day1, hour: 10, minute: 0, calendar: calendar),
            cycleID(prefix: UserNotificationsRepository.IDs.glucoseBeforePrefix, day: day2, hour: 13, minute: 0, calendar: calendar),
            cycleID(prefix: UserNotificationsRepository.IDs.glucoseAfterPrefix, day: day2, hour: 15, minute: 0, calendar: calendar),
            cycleID(prefix: UserNotificationsRepository.IDs.glucoseBeforePrefix, day: day3, hour: 19, minute: 0, calendar: calendar),
            cycleID(prefix: UserNotificationsRepository.IDs.glucoseAfterPrefix, day: day3, hour: 21, minute: 0, calendar: calendar),
            cycleID(prefix: UserNotificationsRepository.IDs.glucoseBedtimePrefix, day: day4, hour: 22, minute: 15, calendar: calendar),
        ])

        XCTAssertEqual(Set(center.pendingRequests.keys), expected)
    }

    private func makeRequest(id: String) -> UNNotificationRequest {
        UNNotificationRequest(
            identifier: id,
            content: UNMutableNotificationContent(),
            trigger: nil
        )
    }

    private func cycleID(prefix: String, day: Date, hour: Int, minute: Int, calendar: Calendar) -> String {
        var dayParts = calendar.dateComponents([.year, .month, .day], from: day)
        dayParts.hour = hour
        dayParts.minute = minute
        let y = dayParts.year ?? 0
        let mo = dayParts.month ?? 0
        let d = dayParts.day ?? 0
        return "\(prefix)d\(String(format: "%04d", y))\(String(format: "%02d", mo))\(String(format: "%02d", d)).\(String(format: "%02d", hour))\(String(format: "%02d", minute))"
    }
}

private final class FakeNotificationCenter: UserNotificationCentering, @unchecked Sendable {
    var authorizationResult: Result<Bool, Error> = .success(true)
    var categories: [UNNotificationCategory] = []
    var pendingRequests: [String: UNNotificationRequest] = [:]
    var deliveredIdentifiers: Set<String> = []
    var removedPendingIdentifiers: [[String]] = []
    var removedDeliveredIdentifiers: [[String]] = []

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        switch authorizationResult {
        case .success(let granted):
            return granted
        case .failure(let error):
            throw error
        }
    }

    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {
        self.categories = Array(categories)
    }

    func addOrReplace(request: UNNotificationRequest) async {
        pendingRequests[request.identifier] = request
    }

    func removePendingNotificationRequests(withIdentifiers ids: [String]) {
        removedPendingIdentifiers.append(ids)
        for id in ids {
            pendingRequests.removeValue(forKey: id)
        }
    }

    func removeDeliveredNotifications(withIdentifiers ids: [String]) {
        removedDeliveredIdentifiers.append(ids)
        for id in ids {
            deliveredIdentifiers.remove(id)
        }
    }

    func removeAllPendingNotificationRequests() {
        pendingRequests.removeAll()
    }

    func removeAllDeliveredNotifications() {
        deliveredIdentifiers.removeAll()
    }

    func pendingRequestIdentifiers() async -> [String] {
        pendingRequests.keys.sorted()
    }

    func deliveredNotificationIdentifiers() async -> [String] {
        deliveredIdentifiers.sorted()
    }
}
