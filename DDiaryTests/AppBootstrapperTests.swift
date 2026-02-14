import XCTest
@testable import DDiary

@MainActor
final class AppBootstrapperTests: XCTestCase {
    func test_makeLaunchState_returnsFailedState_whenModelContainerFactoryThrows() {
        enum TestError: LocalizedError {
            case forced
            var errorDescription: String? { "forced model container failure" }
        }

        let state = AppBootstrapper.makeLaunchState(isUITesting: false) { _, _ in
            throw TestError.forced
        }

        guard case .failed(let message) = state else {
            return XCTFail("Expected failed launch state when model container creation throws")
        }

        XCTAssertTrue(message.contains("Failed to initialize local data storage."))
        XCTAssertTrue(message.contains("forced model container failure"))
    }
}
