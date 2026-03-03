import XCTest
@testable import DDiary

@MainActor
final class NotificationsActionUseCaseTests: XCTestCase {
    func test_skip_logsBloodPressureForBPCategory() async throws {
        let sut = makeSUT()

        await sut.useCase.skip(categoryIdentifier: UserNotificationsRepository.IDs.bpCategory)

        XCTAssertEqual(sut.analytics.scheduleUpdated, [.bloodPressure])
    }

    func test_skip_logsGlucoseForGlucoseCategory() async throws {
        let sut = makeSUT()

        await sut.useCase.skip(categoryIdentifier: UserNotificationsRepository.IDs.glucoseAfterCategory)

        XCTAssertEqual(sut.analytics.scheduleUpdated, [.glucose])
    }

    func test_skip_unknownCategory_doesNotLogScheduleUpdate() async throws {
        let sut = makeSUT()

        await sut.useCase.skip(categoryIdentifier: "unknown.category")

        XCTAssertTrue(sut.analytics.scheduleUpdated.isEmpty)
    }

    func test_snooze_forwardsQuickEntryMetadata() async throws {
        let sut = makeSUT()

        await sut.useCase.snooze(
            originalIdentifier: "ddiary.glucose.before.d20260214.0930",
            minutes: 30,
            title: L10n.notificationGlucoseBeforeLunchTitle,
            body: L10n.notificationGlucoseBeforeLunchBody,
            categoryIdentifier: UserNotificationsRepository.IDs.glucoseBeforeCategory,
            mealSlotRawValue: MealSlot.lunch.rawValue,
            measurementTypeRawValue: GlucoseMeasurementType.beforeMeal.rawValue
        )

        XCTAssertEqual(sut.notifications.snoozeCalls.count, 1)
        let call = try XCTUnwrap(sut.notifications.snoozeCalls.first)
        XCTAssertEqual(call.mealSlotRawValue, MealSlot.lunch.rawValue)
        XCTAssertEqual(call.measurementTypeRawValue, GlucoseMeasurementType.beforeMeal.rawValue)
    }

    private func makeSUT() -> (
        useCase: NotificationsActionUseCase,
        notifications: SpyNotificationsRepository,
        analytics: MockAnalyticsRepository
    ) {
        let notifications = SpyNotificationsRepository()
        let analytics = MockAnalyticsRepository()
        let useCase = NotificationsActionUseCase(
            notificationsRepository: notifications,
            analyticsRepository: analytics
        )
        return (useCase, notifications, analytics)
    }
}

private final class SpyNotificationsRepository: NotificationsRepository, @unchecked Sendable {
    struct SnoozeCall {
        let originalIdentifier: String
        let minutes: Int
        let title: String
        let body: String
        let categoryIdentifier: String
        let mealSlotRawValue: String?
        let measurementTypeRawValue: String?
    }

    struct ScheduleOneOffCall {
        let date: Date
        let identifier: String
        let title: String
        let body: String
        let categoryIdentifier: String
        let userInfo: [AnyHashable: Any]
    }

    private(set) var snoozeCalls: [SnoozeCall] = []
    private(set) var scheduleOneOffCalls: [ScheduleOneOffCall] = []

    func requestAuthorization() async throws -> Bool { true }
    func hasPendingNotificationRequests() async -> Bool { false }

    func scheduleBloodPressure(times: [Int], activeWeekdays: Set<Int>) async throws {}
    func cancelBloodPressure() async {}
    func rescheduleBloodPressure(times: [Int], activeWeekdays: Set<Int>) async throws {}

    func scheduleGlucoseBeforeMeal(
        breakfast: DateComponents,
        lunch: DateComponents,
        dinner: DateComponents,
        isEnabled: Bool
    ) async throws {}

    func scheduleGlucoseAfterMeal2h(
        breakfast: DateComponents,
        lunch: DateComponents,
        dinner: DateComponents,
        isEnabled: Bool
    ) async throws {}

    func scheduleGlucoseBedtime(isEnabled: Bool, time: DateComponents?) async throws {}
    func cancelGlucose() async {}

    func rescheduleGlucose(
        breakfast: DateComponents,
        lunch: DateComponents,
        dinner: DateComponents,
        enableBeforeMeal: Bool,
        enableAfterMeal2h: Bool,
        enableBedtime: Bool,
        bedtimeTime: DateComponents?
    ) async throws {}

    func rescheduleGlucoseCycle(
        configuration: GlucoseCycleConfiguration,
        startDate: Date,
        numberOfDays: Int
    ) async throws {}

    func scheduleOneOff(
        at date: Date,
        identifier: String,
        title: String,
        body: String,
        categoryIdentifier: String,
        userInfo: [AnyHashable: Any]
    ) async {
        scheduleOneOffCalls.append(
            ScheduleOneOffCall(
                date: date,
                identifier: identifier,
                title: title,
                body: body,
                categoryIdentifier: categoryIdentifier,
                userInfo: userInfo
            )
        )
    }

    func snooze(
        originalIdentifier: String,
        minutes: Int,
        title: String,
        body: String,
        categoryIdentifier: String,
        mealSlotRawValue: String?,
        measurementTypeRawValue: String?
    ) async {
        snoozeCalls.append(
            SnoozeCall(
                originalIdentifier: originalIdentifier,
                minutes: minutes,
                title: title,
                body: body,
                categoryIdentifier: categoryIdentifier,
                mealSlotRawValue: mealSlotRawValue,
                measurementTypeRawValue: measurementTypeRawValue
            )
        )
    }

    func cancel(withIdentifier id: String) async {}
    func cancelPlannedBloodPressureNotification(at scheduledDate: Date) async {}
    func cancelPlannedGlucoseNotification(measurementType: GlucoseMeasurementType, at scheduledDate: Date) async {}
    func scheduledReminders(on day: Date) async -> [ScheduledReminder] { [] }
    func cancelAll() async {}
}
