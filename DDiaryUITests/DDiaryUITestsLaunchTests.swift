//
//  DDiaryUITestsLaunchTests.swift
//  DDiaryUITests
//
//  Created by Ilia Khokhlov on 24.11.25.
//

import XCTest

final class DDiaryUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        if ProcessInfo.processInfo.environment["DDIARY_UI_ALL_CONFIGS"] == "1" {
            return true
        }
        return ProcessInfo.processInfo.environment["CI"] == nil
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launchArguments.append("UITESTING")
        app.launch()

        // Insert steps here to perform after app launch but before taking a screenshot,
        // such as logging into a test account or navigating somewhere in the app

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
