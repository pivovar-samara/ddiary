//
//  AnalyticsEnvironmentTests.swift
//  DDiaryTests
//

import Foundation
import XCTest
@testable import DDiary

final class AnalyticsEnvironmentTests: XCTestCase {

    func test_make_withUITestingArgument_disablesCollection() {
        let environment = AnalyticsEnvironment.make(arguments: ["UITESTING"], environment: [:])
        XCTAssertTrue(environment.isUITesting)
        XCTAssertFalse(environment.collectionEnabled)
    }

    func test_make_withUITestingEnvironmentVariable_disablesCollection() {
        let environment = AnalyticsEnvironment.make(arguments: [], environment: ["UITESTING": "1"])
        XCTAssertTrue(environment.isUITesting)
        XCTAssertFalse(environment.collectionEnabled)
    }

    func test_make_withPrettyDataArgument_disablesCollection() {
        let environment = AnalyticsEnvironment.make(arguments: ["PRETTY_DATA"], environment: [:])
        XCTAssertTrue(environment.isPrettyData)
        XCTAssertFalse(environment.collectionEnabled)
    }

    func test_make_withXCTestConfigurationFilePath_disablesCollection() {
        let environment = AnalyticsEnvironment.make(
            arguments: [],
            environment: ["XCTestConfigurationFilePath": "/tmp/whatever.xctestconfiguration"]
        )
        XCTAssertTrue(environment.isUnitTesting)
        XCTAssertFalse(environment.collectionEnabled)
    }

    /// Guards the production path: a clean launch must still be allowed to collect.
    /// Note this asserts on literal inputs — `AnalyticsEnvironment.current()` would
    /// correctly report collection disabled, because XCTestCase is loaded right now.
    func test_make_withCleanArgumentsAndEnvironment_enablesCollection() {
        let environment = AnalyticsEnvironment(
            isUITesting: false,
            isPrettyData: false,
            isUnitTesting: false
        )
        XCTAssertTrue(environment.collectionEnabled)
    }

    /// The whole point of the gate: this very process must not be allowed to send telemetry.
    func test_current_underXCTest_disablesCollection() {
        XCTAssertFalse(AnalyticsEnvironment.current().collectionEnabled)
    }
}
