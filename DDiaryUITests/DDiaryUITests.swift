//
//  DDiaryUITests.swift
//  DDiaryUITests
//
//  Created by Ilia Khokhlov on 24.11.25.
//

import XCTest

final class DDiaryUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
    }

    // Accessibility identifiers used by the app UI.
    private enum A11y {
        enum Tab {
            static let today = "tab.today" // fallback to label "Today"
            static let history = "tab.history" // fallback to label "History"
        }
        enum TodayRowPrefix {
            static let bp = "today.row.bp."
            static let glucose = "today.row.glucose."
        }
        enum Field {
            static let systolic = "quickEntry.bp.systolicField"
            static let diastolic = "quickEntry.bp.diastolicField"
            static let pulse = "quickEntry.bp.pulseField"
            static let glucose = "quickEntry.glucose.valueField"
        }
        enum Action {
            static let save = "quickEntry.save"
        }
    }

    @MainActor
    func testQuickEntryAndHistoryFlow() throws {
        // 1) Launch app
        let app = XCUIApplication()
        app.launch()

        // 2) Navigate to Today (if tab bar exists)
        if app.tabBars.firstMatch.exists {
            let todayButton = app.tabBars.buttons[A11y.Tab.today].exists
            ? app.tabBars.buttons[A11y.Tab.today]
            : app.tabBars.buttons["Today"]
            if waitForExistence(todayButton, timeout: 5) { todayButton.tap() }
        }

        // 3) Open BP Quick Entry by tapping a Today BP row and enter values
        let bpRow = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", A11y.TodayRowPrefix.bp)).firstMatch
        XCTAssertTrue(waitForExistence(bpRow, timeout: 10), "A BP slot row should exist on Today")
        bpRow.tap()

        let systolicField = app.textFields[A11y.Field.systolic]
        XCTAssertTrue(waitForExistence(systolicField, timeout: 5), "Systolic field should exist")
        systolicField.clearAndTypeText("120")

        let diastolicField = app.textFields[A11y.Field.diastolic]
        XCTAssertTrue(waitForExistence(diastolicField, timeout: 5), "Diastolic field should exist")
        diastolicField.clearAndTypeText("80")

        let pulseField = app.textFields[A11y.Field.pulse]
        XCTAssertTrue(waitForExistence(pulseField, timeout: 5), "Pulse field should exist")
        pulseField.clearAndTypeText("72")

        let bpSaveButton = firstExisting(in: [
            app.buttons[A11y.Action.save],
            app.navigationBars.buttons[A11y.Action.save],
            app.buttons["Save"]
        ])
        XCTAssertTrue(waitForExistence(bpSaveButton, timeout: 5), "Save button should exist on BP Quick Entry")
        bpSaveButton.tap()
        _ = waitForNonExistence(systolicField, timeout: 5)

        // 4) Open Glucose Quick Entry by tapping a Today Glucose row and enter values
        let glucoseRow = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", A11y.TodayRowPrefix.glucose)).firstMatch
        XCTAssertTrue(waitForExistence(glucoseRow, timeout: 10), "A Glucose slot row should exist on Today")
        glucoseRow.tap()

        let glucoseField = app.textFields[A11y.Field.glucose]
        XCTAssertTrue(waitForExistence(glucoseField, timeout: 5), "Glucose value field should exist")
        // Enter a simple integer to avoid locale-specific decimal keypad issues
        glucoseField.clearAndTypeText("6")

        let glucoseSaveButton = firstExisting(in: [
            app.buttons[A11y.Action.save],
            app.navigationBars.buttons[A11y.Action.save],
            app.buttons["Save"]
        ])
        XCTAssertTrue(waitForExistence(glucoseSaveButton, timeout: 5), "Save button should exist on Glucose Quick Entry")
        glucoseSaveButton.tap()
        _ = waitForNonExistence(glucoseField, timeout: 5)

        // 5) Navigate to History
        if app.tabBars.firstMatch.exists {
            let historyButton = app.tabBars.buttons[A11y.Tab.history].exists
            ? app.tabBars.buttons[A11y.Tab.history]
            : app.tabBars.buttons["History"]
            XCTAssertTrue(waitForExistence(historyButton, timeout: 5), "History tab button should exist")
            historyButton.tap()
        }

        // 6) Verify at least one BP and one Glucose entry appear in History
        // History uses custom rows without explicit identifiers; verify by badge texts
        let bpBadge = app.staticTexts["BP"].firstMatch
        let gluBadge = app.staticTexts["GLU"].firstMatch
        XCTAssertTrue(waitForExistence(bpBadge, timeout: 10), "Expected at least one BP entry in History")
        XCTAssertTrue(waitForExistence(gluBadge, timeout: 10), "Expected at least one Glucose entry in History")
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    // MARK: - Helpers

    private func waitForExistence(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == true")
        let exp = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter.wait(for: [exp], timeout: timeout)
        return result == .completed
    }

    private func waitForNonExistence(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let exp = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter.wait(for: [exp], timeout: timeout)
        return result == .completed
    }

    @MainActor private func firstExisting(in elements: [XCUIElement]) -> XCUIElement {
        for element in elements where element.exists {
            return element
        }
        return elements.first!
    }
}

private extension XCUIElement {
    func clearAndTypeText(_ text: String) {
        tap()
        if let stringValue = self.value as? String, !stringValue.isEmpty {
            let deleteString = String(repeating: XCUIKeyboardKey.delete.rawValue, count: stringValue.count)
            typeText(deleteString)
        }
        typeText(text)
    }
}

