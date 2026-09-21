//
//  AnalyticsEnvironment.swift
//  DDiary
//

import Foundation

/// Decides whether this process may send telemetry at all.
///
/// Analytics and crash reporting run only in a real user session. Unit tests execute inside
/// the host app (`TEST_HOST = DDiary.app`), so `DDiaryApp.init` runs during `xcodebuild test`
/// too — without this gate a test run would take the production path and emit real events.
public nonisolated struct AnalyticsEnvironment: Sendable, Equatable {
    public let isUITesting: Bool
    public let isPrettyData: Bool
    public let isUnitTesting: Bool

    public var collectionEnabled: Bool {
        !isUITesting && !isPrettyData && !isUnitTesting
    }

    public init(isUITesting: Bool, isPrettyData: Bool, isUnitTesting: Bool) {
        self.isUITesting = isUITesting
        self.isPrettyData = isPrettyData
        self.isUnitTesting = isUnitTesting
    }

    /// Pure seam. `ProcessInfo` cannot be faked, so this is what the tests drive.
    public static func make(
        arguments: [String],
        environment: [String: String]
    ) -> AnalyticsEnvironment {
        AnalyticsEnvironment(
            isUITesting: arguments.contains("UITESTING") || environment["UITESTING"] == "1",
            isPrettyData: arguments.contains("PRETTY_DATA") || environment["PRETTY_DATA"] == "1",
            isUnitTesting: environment["XCTestConfigurationFilePath"] != nil
                || environment["XCTestBundlePath"] != nil
                || NSClassFromString("XCTestCase") != nil
        )
    }

    public static func current() -> AnalyticsEnvironment {
        make(
            arguments: ProcessInfo.processInfo.arguments,
            environment: ProcessInfo.processInfo.environment
        )
    }
}
