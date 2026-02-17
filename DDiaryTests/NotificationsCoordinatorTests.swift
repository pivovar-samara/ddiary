import XCTest
@testable import DDiary

@MainActor
final class NotificationsCoordinatorTests: XCTestCase {
    func test_handleAction_enterRoutesToQuickEntryAndCallsCompletion() async {
        let completionCalled = expectation(description: "completion called")
        let actionHandler = BlockingNotificationsActionHandler(
            skipStarted: nil,
            snoozeStarted: nil,
            moveStarted: nil,
            gate: AsyncGate()
        )
        let quickEntryRouter = SpyQuickEntryRouter()
        let sut = NotificationsCoordinator(
            actionHandler: actionHandler,
            quickEntryRouter: quickEntryRouter
        )

        sut.handleAction(
            .enter,
            context: NotificationActionContext(
                identifier: "ddiary.glucose.before.0800",
                categoryIdentifier: UserNotificationsRepository.IDs.glucoseBeforeCategory,
                title: L10n.notificationGlucoseBeforeBreakfastTitle,
                body: "Before breakfast",
                mealSlotRawValue: MealSlot.breakfast.rawValue,
                measurementTypeRawValue: GlucoseMeasurementType.beforeMeal.rawValue
            ),
            completionHandler: {
                completionCalled.fulfill()
            }
        )

        await fulfillment(of: [completionCalled], timeout: 1.0)
        XCTAssertEqual(quickEntryRouter.receivedContexts.count, 1)
        XCTAssertEqual(quickEntryRouter.receivedContexts.first?.identifier, "ddiary.glucose.before.0800")
    }

    func test_handleAction_waitsForAsyncSkipBeforeCallingCompletion() async {
        let skipStarted = expectation(description: "skip started")
        let completionCalled = expectation(description: "completion called")
        let gate = AsyncGate()
        let actionHandler = BlockingNotificationsActionHandler(
            skipStarted: skipStarted,
            snoozeStarted: nil,
            moveStarted: nil,
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
                measurementTypeRawValue: nil
            ),
            completionHandler: {
                didCallCompletion = true
                completionCalled.fulfill()
            }
        )

        await fulfillment(of: [skipStarted], timeout: 1.0)
        XCTAssertFalse(didCallCompletion)
        XCTAssertFalse(actionHandler.didFinishSkip)

        await gate.open()

        await fulfillment(of: [completionCalled], timeout: 1.0)
        XCTAssertTrue(actionHandler.didFinishSkip)
    }

    func test_handleAction_waitsForAsyncSnoozeBeforeCallingCompletion_andForwardsContext() async {
        let snoozeStarted = expectation(description: "snooze started")
        let completionCalled = expectation(description: "completion called")
        let gate = AsyncGate()
        let actionHandler = BlockingNotificationsActionHandler(
            skipStarted: nil,
            snoozeStarted: snoozeStarted,
            moveStarted: nil,
            gate: gate
        )
        let sut = NotificationsCoordinator(actionHandler: actionHandler)

        let context = NotificationActionContext(
            identifier: "ddiary.glucose.before.0800",
            categoryIdentifier: UserNotificationsRepository.IDs.glucoseBeforeCategory,
            title: "Glucose reminder",
            body: "Before breakfast",
            mealSlotRawValue: nil,
            measurementTypeRawValue: nil
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

        await gate.open()

        await fulfillment(of: [completionCalled], timeout: 1.0)
        XCTAssertTrue(actionHandler.didFinishSnooze)
    }

    func test_handleAction_waitsForAsyncMoveBeforeCallingCompletion() async {
        let moveStarted = expectation(description: "move started")
        let completionCalled = expectation(description: "completion called")
        let gate = AsyncGate()
        let actionHandler = BlockingNotificationsActionHandler(
            skipStarted: nil,
            snoozeStarted: nil,
            moveStarted: moveStarted,
            gate: gate
        )
        let sut = NotificationsCoordinator(actionHandler: actionHandler)

        var didCallCompletion = false
        sut.handleAction(
            .moveToDinner,
            context: NotificationActionContext(
                identifier: "ddiary.glucose.before.0800",
                categoryIdentifier: UserNotificationsRepository.IDs.glucoseBeforeCategory,
                title: "Glucose reminder",
                body: "Before breakfast",
                mealSlotRawValue: nil,
                measurementTypeRawValue: nil
            ),
            completionHandler: {
                didCallCompletion = true
                completionCalled.fulfill()
            }
        )

        await fulfillment(of: [moveStarted], timeout: 1.0)
        XCTAssertFalse(didCallCompletion)
        XCTAssertFalse(actionHandler.didFinishMove)
        XCTAssertEqual(actionHandler.receivedMoveMeal, .dinner)

        await gate.open()

        await fulfillment(of: [completionCalled], timeout: 1.0)
        XCTAssertTrue(actionHandler.didFinishMove)
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
    private let snoozeStarted: XCTestExpectation?
    private let moveStarted: XCTestExpectation?
    private let gate: AsyncGate
    private(set) var didFinishSkip = false
    private(set) var didFinishSnooze = false
    private(set) var didFinishMove = false
    private(set) var receivedSnoozeIdentifier: String?
    private(set) var receivedSnoozeMinutes: Int?
    private(set) var receivedSnoozeTitle: String?
    private(set) var receivedSnoozeBody: String?
    private(set) var receivedSnoozeCategoryIdentifier: String?
    private(set) var receivedMoveMeal: MealSlot?

    init(
        skipStarted: XCTestExpectation?,
        snoozeStarted: XCTestExpectation?,
        moveStarted: XCTestExpectation?,
        gate: AsyncGate
    ) {
        self.skipStarted = skipStarted
        self.snoozeStarted = snoozeStarted
        self.moveStarted = moveStarted
        self.gate = gate
    }

    func skip() async {
        guard let skipStarted else {
            XCTFail("Unexpected skip call")
            return
        }
        skipStarted.fulfill()
        await gate.wait()
        didFinishSkip = true
    }

    func snooze(originalIdentifier: String, minutes: Int, title: String, body: String, categoryIdentifier: String) async {
        guard let snoozeStarted else {
            XCTFail("Unexpected snooze call")
            return
        }
        receivedSnoozeIdentifier = originalIdentifier
        receivedSnoozeMinutes = minutes
        receivedSnoozeTitle = title
        receivedSnoozeBody = body
        receivedSnoozeCategoryIdentifier = categoryIdentifier
        snoozeStarted.fulfill()
        await gate.wait()
        didFinishSnooze = true
    }

    func moveBeforeBreakfast(to meal: MealSlot) async {
        guard let moveStarted else {
            XCTFail("Unexpected move call")
            return
        }
        receivedMoveMeal = meal
        moveStarted.fulfill()
        await gate.wait()
        didFinishMove = true
    }
}

@MainActor
private final class SpyQuickEntryRouter: NotificationQuickEntryRouting {
    private(set) var receivedContexts: [NotificationActionContext] = []

    func routeToQuickEntry(context: NotificationActionContext) {
        receivedContexts.append(context)
    }
}
