import XCTest
@testable import DDiary

@MainActor
final class GoogleRefreshTokenObserverRegistryTests: XCTestCase {
    func test_install_replacesPreviousObserver() async {
        let center = NotificationCenter()
        let registry = GoogleRefreshTokenObserverRegistry()
        let firstHandlerCalled = expectation(description: "first handler should not be called")
        firstHandlerCalled.isInverted = true
        let secondHandlerCalled = expectation(description: "second handler called")

        registry.install(center: center) { _ in
            firstHandlerCalled.fulfill()
        }
        registry.install(center: center) { _ in
            secondHandlerCalled.fulfill()
        }

        center.post(
            name: .googleRefreshTokenUpdated,
            object: nil,
            userInfo: ["refreshToken": "rt-1"]
        )

        await fulfillment(of: [secondHandlerCalled, firstHandlerCalled], timeout: 0.5)
    }

    func test_install_ignoresInvalidPayload() async {
        let center = NotificationCenter()
        let registry = GoogleRefreshTokenObserverRegistry()
        let handlerCalled = expectation(description: "handler should not be called")
        handlerCalled.isInverted = true

        registry.install(center: center) { _ in
            handlerCalled.fulfill()
        }

        center.post(name: .googleRefreshTokenUpdated, object: nil, userInfo: nil)
        center.post(name: .googleRefreshTokenUpdated, object: nil, userInfo: ["refreshToken": 123])

        await fulfillment(of: [handlerCalled], timeout: 0.2)
    }
}
