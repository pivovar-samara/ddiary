import XCTest
@testable import DDiary

@MainActor
final class NotificationsCoordinatorTests: XCTestCase {
    func test_handleAction_waitsForAsyncSkipBeforeCallingCompletion() async {
        let skipStarted = expectation(description: "skip started")
        let completionCalled = expectation(description: "completion called")
        let gate = AsyncGate()
        let actionHandler = BlockingNotificationsActionHandler(skipStarted: skipStarted, gate: gate)
        let sut = NotificationsCoordinator(actionHandler: actionHandler)

        var didCallCompletion = false
        sut.handleAction(
            .skip,
            context: NotificationActionContext(
                identifier: "ddiary.glucose.before.0800",
                categoryIdentifier: UserNotificationsRepository.IDs.glucoseBeforeCategory,
                title: "Glucose reminder",
                body: "Before breakfast"
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
    private let skipStarted: XCTestExpectation
    private let gate: AsyncGate
    private(set) var didFinishSkip = false

    init(skipStarted: XCTestExpectation, gate: AsyncGate) {
        self.skipStarted = skipStarted
        self.gate = gate
    }

    func skip() async {
        skipStarted.fulfill()
        await gate.wait()
        didFinishSkip = true
    }

    func snooze(originalIdentifier: String, minutes: Int, title: String, body: String, categoryIdentifier: String) async {
        XCTFail("Unexpected snooze call")
    }

    func moveBeforeBreakfast(to meal: MealSlot) async {
        XCTFail("Unexpected move call")
    }
}
