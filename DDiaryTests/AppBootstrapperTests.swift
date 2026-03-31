import SwiftData
import XCTest
@testable import DDiary

@MainActor
final class AppBootstrapperTests: XCTestCase {
    func test_makeLaunchState_returnsReadyState_whenCloudKitInitializationSucceeds() throws {
        var capturedConfigurations: [ModelConfiguration] = []

        let state = AppBootstrapper.makeLaunchState(
            isUITesting: false,
            appContainerFactory: { _ in Self.previewAppContainer },
            modelContainerFactory: { schema, configurations in
                capturedConfigurations = configurations
                return try Self.makeModelContainer(schema: schema)
            }
        )

        guard case let .ready(_, _, launchNotice) = state else {
            return XCTFail("Expected ready launch state when CloudKit-backed model container creation succeeds")
        }

        XCTAssertNil(launchNotice)
        XCTAssertEqual(capturedConfigurations.count, 1)
        XCTAssertFalse(capturedConfigurations[0].isStoredInMemoryOnly)
        XCTAssertTrue(cloudKitDatabaseDescription(for: capturedConfigurations[0]).contains("private"))
        XCTAssertTrue(cloudKitDatabaseDescription(for: capturedConfigurations[0]).contains("iCloud.container.diary"))
    }

    func test_makeLaunchState_returnsReadyState_whenCloudKitInitializationFailsButLocalFallbackSucceeds() throws {
        enum TestError: LocalizedError {
            case cloudKit

            var errorDescription: String? {
                switch self {
                case .cloudKit:
                    return "forced CloudKit failure"
                }
            }
        }

        var capturedConfigurations: [ModelConfiguration] = []
        var invocationCount = 0

        let state = AppBootstrapper.makeLaunchState(
            isUITesting: false,
            appContainerFactory: { _ in Self.previewAppContainer },
            modelContainerFactory: { schema, configurations in
                invocationCount += 1
                capturedConfigurations.append(contentsOf: configurations)

                if invocationCount == 1 {
                    throw TestError.cloudKit
                }

                return try Self.makeModelContainer(schema: schema)
            }
        )

        guard case let .ready(_, _, launchNotice) = state else {
            return XCTFail("Expected ready launch state when local fallback succeeds")
        }

        XCTAssertEqual(invocationCount, 2)
        XCTAssertEqual(launchNotice, .cloudSyncUnavailable)
        XCTAssertEqual(capturedConfigurations.count, 2)
        XCTAssertFalse(capturedConfigurations[1].isStoredInMemoryOnly)
        XCTAssertTrue(cloudKitDatabaseDescription(for: capturedConfigurations[0]).contains("private"))
        XCTAssertTrue(cloudKitDatabaseDescription(for: capturedConfigurations[0]).contains("iCloud.container.diary"))
        XCTAssertTrue(cloudKitDatabaseDescription(for: capturedConfigurations[1]).contains("none"))
    }

    func test_makeLaunchState_returnsFailedState_whenCloudKitAndLocalFallbackInitializationFail() {
        enum TestError: LocalizedError {
            case cloudKit
            case localFallback

            var errorDescription: String? {
                switch self {
                case .cloudKit:
                    return "forced CloudKit failure"
                case .localFallback:
                    return "forced local fallback failure"
                }
            }
        }

        var invocationCount = 0

        let state = AppBootstrapper.makeLaunchState(
            isUITesting: false,
            appContainerFactory: { _ in Self.previewAppContainer },
            modelContainerFactory: { _, _ in
                invocationCount += 1

                switch invocationCount {
                case 1:
                    throw TestError.cloudKit
                default:
                    throw TestError.localFallback
                }
            }
        )

        guard case .failed(let message) = state else {
            return XCTFail("Expected failed launch state when CloudKit and local fallback both throw")
        }

        XCTAssertEqual(invocationCount, 2)
        XCTAssertTrue(message.contains("Failed to initialize local data storage."))
        XCTAssertTrue(message.contains("forced local fallback failure"))
    }

    func test_makeLaunchState_usesSingleInMemoryConfiguration_whenUITesting() throws {
        var capturedConfigurations: [ModelConfiguration] = []
        var invocationCount = 0

        let state = AppBootstrapper.makeLaunchState(
            isUITesting: true,
            appContainerFactory: { _ in Self.previewAppContainer },
            modelContainerFactory: { schema, configurations in
                invocationCount += 1
                capturedConfigurations = configurations
                return try Self.makeModelContainer(schema: schema)
            }
        )

        guard case let .ready(_, _, launchNotice) = state else {
            return XCTFail("Expected ready launch state in UI testing mode")
        }

        XCTAssertEqual(invocationCount, 1)
        XCTAssertNil(launchNotice)
        XCTAssertEqual(capturedConfigurations.count, 1)
        XCTAssertTrue(capturedConfigurations[0].isStoredInMemoryOnly)
        XCTAssertTrue(cloudKitDatabaseDescription(for: capturedConfigurations[0]).contains("none"))
    }

    func test_makeLaunchState_usesSingleInMemoryConfiguration_whenPrettyDataModeEnabled() throws {
        var capturedConfigurations: [ModelConfiguration] = []
        var invocationCount = 0

        let state = AppBootstrapper.makeLaunchState(
            isUITesting: false,
            usesPrettyData: true,
            appContainerFactory: { _ in Self.previewAppContainer },
            prettyDataAppContainerFactory: { _ in Self.previewAppContainer },
            modelContainerFactory: { schema, configurations in
                invocationCount += 1
                capturedConfigurations = configurations
                return try Self.makeModelContainer(schema: schema)
            }
        )

        guard case let .ready(_, _, launchNotice) = state else {
            return XCTFail("Expected ready launch state in pretty-data mode")
        }

        XCTAssertEqual(invocationCount, 1)
        XCTAssertNil(launchNotice)
        XCTAssertEqual(capturedConfigurations.count, 1)
        XCTAssertTrue(capturedConfigurations[0].isStoredInMemoryOnly)
        XCTAssertTrue(cloudKitDatabaseDescription(for: capturedConfigurations[0]).contains("none"))
    }

    private static func makeModelContainer(schema: Schema) throws -> ModelContainer {
        try ModelContainer(
            for: schema,
            configurations: [
                ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: true,
                    cloudKitDatabase: .none
                )
            ]
        )
    }

    private static let previewAppContainer: AppContainer = .preview

    private func cloudKitDatabaseDescription(for configuration: ModelConfiguration) -> String {
        String(describing: configuration.cloudKitDatabase)
    }
}
