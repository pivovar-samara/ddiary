import XCTest
@testable import DDiary

@MainActor
final class NotificationsCoordinatorTests: XCTestCase {
    func test_handleAction_enterRoutesToQuickEntryAndCallsCompletion() async {
        let completionCalled = expectation(description: "completion called")
        let actionHandler = BlockingNotificationsActionHandler(
            skipStarted: nil,
            snoozeStarted: nil,
            gate: AsyncGate()
        )
        let quickEntryRouter = SpyQuickEntryRouter()
        let sut = NotificationsCoordinator(
            actionHandler: actionHandler,
            quickEntryRouter: quickEntryRouter
        )

        var didCallCompletion = false
        sut.handleAction(
            .enter,
            context: NotificationActionContext(
                identifier: "ddiary.glucose.before.0800",
                categoryIdentifier: UserNotificationsRepository.IDs.glucoseBeforeCategory,
                title: L10n.notificationGlucoseBeforeBreakfastTitle,
                body: "Before breakfast",
                mealSlotRawValue: MealSlot.breakfast.rawValue,
                measurementTypeRawValue: GlucoseMeasurementType.beforeMeal.rawValue,
                deliveredDate: nil
            ),
            completionHandler: {
                didCallCompletion = true
                completionCalled.fulfill()
            }
        )

        XCTAssertTrue(didCallCompletion)
        await fulfillment(of: [completionCalled], timeout: 1.0)
        await Task.yield()
        XCTAssertEqual(quickEntryRouter.receivedContexts.count, 1)
        XCTAssertEqual(quickEntryRouter.receivedContexts.first?.identifier, "ddiary.glucose.before.0800")
    }

    func test_handleAction_callsCompletionAfterAsyncSkipCompletes() async {
        let skipStarted = expectation(description: "skip started")
        let skipFinished = expectation(description: "skip finished")
        let completionCalled = expectation(description: "completion called")
        let gate = AsyncGate()
        let actionHandler = BlockingNotificationsActionHandler(
            skipStarted: skipStarted,
            skipFinished: skipFinished,
            snoozeStarted: nil,
            gate: gate
        )
        let sut = NotificationsCoordinator(actionHandler: actionHandler)

        var didCallCompletion = false
        sut.handleAction(
            .skip,
            context: NotificationActionContext(
                identifier: "ddiary.glucose.before.0800",
                categoryIdentifier: UserNotificationsRepository.IDs.glucoseBeforeCategory,
                title: "Glucose reminder",
                body: "Before breakfast",
                mealSlotRawValue: nil,
                measurementTypeRawValue: nil,
                deliveredDate: nil
            ),
            completionHandler: {
                didCallCompletion = true
                completionCalled.fulfill()
            }
        )

        await fulfillment(of: [skipStarted], timeout: 1.0)
        XCTAssertFalse(didCallCompletion)
        XCTAssertFalse(actionHandler.didFinishSkip)
        XCTAssertEqual(
            actionHandler.receivedSkipCategoryIdentifier,
            UserNotificationsRepository.IDs.glucoseBeforeCategory
        )

        await gate.open()

        await fulfillment(of: [skipFinished, completionCalled], timeout: 1.0)
        XCTAssertTrue(actionHandler.didFinishSkip)
        XCTAssertTrue(didCallCompletion)
    }

    func test_handleAction_skipForwardsNotificationIdentifier() async {
        let skipStarted = expectation(description: "skip started")
        let skipFinished = expectation(description: "skip finished")
        let gate = AsyncGate()
        let actionHandler = BlockingNotificationsActionHandler(
            skipStarted: skipStarted,
            skipFinished: skipFinished,
            snoozeStarted: nil,
            gate: gate
        )
        let sut = NotificationsCoordinator(actionHandler: actionHandler)

        let expectedIdentifier = "ddiary.bp.d20260216.0900"
        sut.handleAction(
            .skip,
            context: NotificationActionContext(
                identifier: expectedIdentifier,
                categoryIdentifier: UserNotificationsRepository.IDs.bpCategory,
                title: L10n.notificationBPTitle,
                body: L10n.notificationBPBody,
                mealSlotRawValue: nil,
                measurementTypeRawValue: nil,
                deliveredDate: nil
            ),
            completionHandler: {}
        )

        await fulfillment(of: [skipStarted], timeout: 1.0)
        XCTAssertEqual(actionHandler.receivedSkipIdentifier, expectedIdentifier)
        XCTAssertEqual(
            actionHandler.receivedSkipCategoryIdentifier,
            UserNotificationsRepository.IDs.bpCategory
        )

        await gate.open()
        await fulfillment(of: [skipFinished], timeout: 1.0)
    }

    func test_handleAction_callsCompletionAfterAsyncSnoozeCompletes_andForwardsContext() async {
        let snoozeStarted = expectation(description: "snooze started")
        let snoozeFinished = expectation(description: "snooze finished")
        let completionCalled = expectation(description: "completion called")
        let gate = AsyncGate()
        let actionHandler = BlockingNotificationsActionHandler(
            skipStarted: nil,
            snoozeStarted: snoozeStarted,
            snoozeFinished: snoozeFinished,
            gate: gate
        )
        let sut = NotificationsCoordinator(actionHandler: actionHandler)

        let context = NotificationActionContext(
            identifier: "ddiary.glucose.before.0800",
            categoryIdentifier: UserNotificationsRepository.IDs.glucoseBeforeCategory,
            title: "Glucose reminder",
            body: "Before breakfast",
            mealSlotRawValue: MealSlot.breakfast.rawValue,
            measurementTypeRawValue: GlucoseMeasurementType.beforeMeal.rawValue,
            deliveredDate: nil
        )

        var didCallCompletion = false
        sut.handleAction(
            .snooze(minutes: 30),
            context: context,
            completionHandler: {
                didCallCompletion = true
                completionCalled.fulfill()
            }
        )

        await fulfillment(of: [snoozeStarted], timeout: 1.0)
        XCTAssertFalse(didCallCompletion)
        XCTAssertFalse(actionHandler.didFinishSnooze)
        XCTAssertEqual(actionHandler.receivedSnoozeMinutes, 30)
        XCTAssertEqual(actionHandler.receivedSnoozeIdentifier, context.identifier)
        XCTAssertEqual(actionHandler.receivedSnoozeTitle, context.title)
        XCTAssertEqual(actionHandler.receivedSnoozeBody, context.body)
        XCTAssertEqual(actionHandler.receivedSnoozeCategoryIdentifier, context.categoryIdentifier)
        XCTAssertEqual(actionHandler.receivedSnoozeMealSlotRawValue, context.mealSlotRawValue)
        XCTAssertEqual(actionHandler.receivedSnoozeMeasurementTypeRawValue, context.measurementTypeRawValue)

        await gate.open()

        await fulfillment(of: [snoozeFinished, completionCalled], timeout: 1.0)
        XCTAssertTrue(actionHandler.didFinishSnooze)
        XCTAssertTrue(didCallCompletion)
    }

    func test_routeToQuickEntry_prefersIdentifierScheduledDateOverDeliveredDate() async throws {
        let router = NotificationQuickEntryRouter(notificationCenter: NotificationCenter())
        let deliveredDate = Date(timeIntervalSince1970: 1_770_700_800)

        router.routeToQuickEntry(
            context: NotificationActionContext(
                identifier: "ddiary.bp.d20260214.0900",
                categoryIdentifier: UserNotificationsRepository.IDs.bpCategory,
                title: L10n.notificationBPTitle,
                body: L10n.notificationBPBody,
                mealSlotRawValue: nil,
                measurementTypeRawValue: nil,
                deliveredDate: deliveredDate
            )
        )

        let request = try XCTUnwrap(router.consumePendingRequest())
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Calendar.current.timeZone
        let expected = try XCTUnwrap(
            calendar.date(
                from: DateComponents(
                    timeZone: calendar.timeZone,
                    year: 2026,
                    month: 2,
                    day: 14,
                    hour: 9,
                    minute: 0
                )
            )
        )

        XCTAssertEqual(request.target, .bloodPressure)
        XCTAssertEqual(request.scheduledDate, expected)
    }

    func test_routeToQuickEntry_usesDeliveredDateWhenIdentifierHasNoScheduledDateToken() async {
        let router = NotificationQuickEntryRouter(notificationCenter: NotificationCenter())
        let deliveredDate = Date(timeIntervalSince1970: 1_770_700_800)

        router.routeToQuickEntry(
            context: NotificationActionContext(
                identifier: "ddiary.bp.0900",
                categoryIdentifier: UserNotificationsRepository.IDs.bpCategory,
                title: L10n.notificationBPTitle,
                body: L10n.notificationBPBody,
                mealSlotRawValue: nil,
                measurementTypeRawValue: nil,
                deliveredDate: deliveredDate
            )
        )

        let request = router.consumePendingRequest()
        XCTAssertEqual(request?.target, .bloodPressure)
        XCTAssertEqual(request?.scheduledDate, deliveredDate)
    }

    func test_routeToQuickEntry_parsesDateFromIdentifierWhenDeliveredDateMissing() async throws {
        let router = NotificationQuickEntryRouter(notificationCenter: NotificationCenter())

        router.routeToQuickEntry(
            context: NotificationActionContext(
                identifier: "ddiary.bp.d20260214.0930",
                categoryIdentifier: UserNotificationsRepository.IDs.bpCategory,
                title: L10n.notificationBPTitle,
                body: L10n.notificationBPBody,
                mealSlotRawValue: nil,
                measurementTypeRawValue: nil,
                deliveredDate: nil
            )
        )

        let request = try XCTUnwrap(router.consumePendingRequest())
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Calendar.current.timeZone
        let expected = try XCTUnwrap(
            calendar.date(
                from: DateComponents(
                    timeZone: calendar.timeZone,
                    year: 2026,
                    month: 2,
                    day: 14,
                    hour: 9,
                    minute: 30
                )
            )
        )

        XCTAssertEqual(request.target, .bloodPressure)
        XCTAssertEqual(request.scheduledDate, expected)
    }

    func test_routeToQuickEntry_rejectsMalformedIdentifierDateToken() async throws {
        let router = NotificationQuickEntryRouter(notificationCenter: NotificationCenter())

        router.routeToQuickEntry(
            context: NotificationActionContext(
                identifier: "ddiary.bp.d20260229.2561",
                categoryIdentifier: UserNotificationsRepository.IDs.bpCategory,
                title: L10n.notificationBPTitle,
                body: L10n.notificationBPBody,
                mealSlotRawValue: nil,
                measurementTypeRawValue: nil,
                deliveredDate: nil
            )
        )

        let request = try XCTUnwrap(router.consumePendingRequest())
        XCTAssertEqual(request.target, .bloodPressure)
        XCTAssertNil(request.scheduledDate)
    }

    func test_routeToQuickEntry_snoozedIdentifierPrefersOriginalDateTokenOverDeliveredDate() async throws {
        let router = NotificationQuickEntryRouter(notificationCenter: NotificationCenter())
        let deliveredDate = Date(timeIntervalSince1970: 1_770_700_800)

        router.routeToQuickEntry(
            context: NotificationActionContext(
                identifier: "ddiary.glucose.before.d20260214.0930.snooze.30",
                categoryIdentifier: UserNotificationsRepository.IDs.glucoseBeforeCategory,
                title: L10n.notificationGlucoseBeforeLunchTitle,
                body: L10n.notificationGlucoseBeforeLunchBody,
                mealSlotRawValue: MealSlot.lunch.rawValue,
                measurementTypeRawValue: GlucoseMeasurementType.beforeMeal.rawValue,
                deliveredDate: deliveredDate
            )
        )

        let request = try XCTUnwrap(router.consumePendingRequest())
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Calendar.current.timeZone
        let expectedOriginalDate = try XCTUnwrap(
            calendar.date(
                from: DateComponents(
                    timeZone: calendar.timeZone,
                    year: 2026,
                    month: 2,
                    day: 14,
                    hour: 9,
                    minute: 30
                )
            )
        )

        XCTAssertEqual(
            request.target,
            .glucose(mealSlot: .lunch, measurementType: .beforeMeal)
        )
        XCTAssertEqual(request.scheduledDate, expectedOriginalDate)
    }
}

private actor AsyncGate {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func open() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class BlockingNotificationsActionHandler: NotificationsActionHandling {
    private let skipStarted: XCTestExpectation?
    private let skipFinished: XCTestExpectation?
    private let snoozeStarted: XCTestExpectation?
    private let snoozeFinished: XCTestExpectation?
    private let gate: AsyncGate
    private(set) var didFinishSkip = false
    private(set) var didFinishSnooze = false
    private(set) var receivedSkipIdentifier: String?
    private(set) var receivedSkipCategoryIdentifier: String?
    private(set) var receivedSnoozeIdentifier: String?
    private(set) var receivedSnoozeMinutes: Int?
    private(set) var receivedSnoozeTitle: String?
    private(set) var receivedSnoozeBody: String?
    private(set) var receivedSnoozeCategoryIdentifier: String?
    private(set) var receivedSnoozeMealSlotRawValue: String?
    private(set) var receivedSnoozeMeasurementTypeRawValue: String?

    init(
        skipStarted: XCTestExpectation?,
        skipFinished: XCTestExpectation? = nil,
        snoozeStarted: XCTestExpectation?,
        snoozeFinished: XCTestExpectation? = nil,
        gate: AsyncGate
    ) {
        self.skipStarted = skipStarted
        self.skipFinished = skipFinished
        self.snoozeStarted = snoozeStarted
        self.snoozeFinished = snoozeFinished
        self.gate = gate
    }

    func skip(identifier: String, categoryIdentifier: String) async {
        guard let skipStarted else {
            XCTFail("Unexpected skip call")
            return
        }
        receivedSkipIdentifier = identifier
        receivedSkipCategoryIdentifier = categoryIdentifier
        skipStarted.fulfill()
        await gate.wait()
        didFinishSkip = true
        skipFinished?.fulfill()
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
        guard let snoozeStarted else {
            XCTFail("Unexpected snooze call")
            return
        }
        receivedSnoozeIdentifier = originalIdentifier
        receivedSnoozeMinutes = minutes
        receivedSnoozeTitle = title
        receivedSnoozeBody = body
        receivedSnoozeCategoryIdentifier = categoryIdentifier
        receivedSnoozeMealSlotRawValue = mealSlotRawValue
        receivedSnoozeMeasurementTypeRawValue = measurementTypeRawValue
        snoozeStarted.fulfill()
        await gate.wait()
        didFinishSnooze = true
        snoozeFinished?.fulfill()
    }
}

@MainActor
private final class SpyQuickEntryRouter: NotificationQuickEntryRouting {
    private(set) var receivedContexts: [NotificationActionContext] = []

    func routeToQuickEntry(context: NotificationActionContext) {
        receivedContexts.append(context)
    }
}
