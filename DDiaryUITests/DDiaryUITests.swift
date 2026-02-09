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
        let shouldLandscape = ProcessInfo.processInfo.environment["UITEST_LANDSCAPE"] == "1"
        Task { @MainActor in
            XCUIDevice.shared.orientation = shouldLandscape ? .landscapeLeft : .portrait
        }
    }

    override func tearDownWithError() throws {
        Task { @MainActor in
            XCUIDevice.shared.orientation = .portrait
        }
    }

    // Accessibility identifiers used by the app UI.
    private enum A11y {
        enum Tab {
            static let today = "tab.today" // fallback to label "Today"
            static let history = "tab.history" // fallback to label "History"
            static let settings = "tab.settings" // fallback to label "Settings"
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
            static let cancel = "quickEntry.cancel"
        }
        enum Settings {
            static let bedtimeSlotEnabled = "settings.bedtimeSlotEnabled"
            static let glucoseBeforeMeal = "settings.glucose.beforeMeal"
            static let glucoseAfterMeal2h = "settings.glucose.afterMeal2h"
            static let glucoseBedtime = "settings.glucose.bedtime"
        }
        enum Today {
            static let completedDisclosure = "today.completedDisclosure"
        }
    }

    @MainActor
    func testQuickEntryAndHistoryFlow() throws {
        // 1) Launch app
        let app = makeApp()
        app.launch()

        // 2) Navigate to Today (if tab bar exists)
        if app.tabBars.firstMatch.exists {
            let todayButton = app.tabBars.buttons[A11y.Tab.today].exists
            ? app.tabBars.buttons[A11y.Tab.today]
            : app.tabBars.buttons["Today"]
            if waitForExistence(todayButton, timeout: 5) { todayButton.tap() }
        }
        _ = waitForExistence(app.scrollViews["today.scroll"], timeout: 5)

        // 3) Open BP Quick Entry by tapping a Today BP row and enter values
        ensureBPSlotExists(app: app)
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
        ensureGlucoseSlotExists(app: app)
        let glucoseRow = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", A11y.TodayRowPrefix.glucose)).firstMatch
        XCTAssertTrue(waitForExistence(glucoseRow, timeout: 10), "A Glucose slot row should exist on Today")
        glucoseRow.tap()

        let glucoseField = app.textFields[A11y.Field.glucose]
        XCTAssertTrue(waitForExistence(glucoseField, timeout: 5), "Glucose value field should exist")
        // Enter a value that matches the current unit to avoid out-of-range warnings
        let unitLabel = app.staticTexts["quickEntry.glucose.unitLabel"]
        XCTAssertTrue(waitForExistence(unitLabel, timeout: 5), "Glucose unit label should exist")
        let unitText = unitLabel.label.lowercased()
        let glucoseValue = unitText.contains("mg/dl") ? "100" : "6"
        glucoseField.clearAndTypeText(glucoseValue)

        let glucoseSaveButton = firstExisting(in: [
            app.buttons[A11y.Action.save],
            app.navigationBars.buttons[A11y.Action.save],
            app.buttons["Save"]
        ])
        XCTAssertTrue(waitForExistence(glucoseSaveButton, timeout: 5), "Save button should exist on Glucose Quick Entry")
        glucoseSaveButton.tap()
        dismissUnusualValuesAlertIfPresent(app: app)
        _ = waitForNonExistence(glucoseField, timeout: 5)

        // 5) Navigate to History (robust helper waits for screen)
        navigateToTab(app: app, tabId: A11y.Tab.history, fallbackLabel: "History")
        let historyList = app.otherElements["history.list"]
        let historyScroll = app.scrollViews["history.scroll"]
        XCTAssertTrue(waitForExistence(historyList, timeout: 10) || waitForExistence(historyScroll, timeout: 10), "History list should be visible")

        // 6) Verify at least one BP and one Glucose entry appear in History using stable row identifiers
        let bpHistoryRow = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "history.row.bp.")).firstMatch
        scrollToElement(bpHistoryRow, in: app, maxSwipes: 8)
        var bpFound = waitForExistence(bpHistoryRow, timeout: 10)
        if !bpFound {
            // Fallback to badge text if row identifiers are not available yet
            let bpBadge = app.staticTexts["BP"].firstMatch
            scrollToElement(bpBadge, in: app, maxSwipes: 8)
            bpFound = waitForExistence(bpBadge, timeout: 5)
        }
        XCTAssertTrue(bpFound, "Expected at least one BP entry in History")

        let gluHistoryRow = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "history.row.glucose.")).firstMatch
        scrollToElement(gluHistoryRow, in: app, maxSwipes: 8)
        var gluFound = waitForExistence(gluHistoryRow, timeout: 10)
        if !gluFound {
            let gluBadge = app.staticTexts["GLU"].firstMatch
            scrollToElement(gluBadge, in: app, maxSwipes: 8)
            gluFound = waitForExistence(gluBadge, timeout: 5)
        }
        XCTAssertTrue(gluFound, "Expected at least one Glucose entry in History")
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let app = makeApp()
            app.launch()
        }
    }

    @MainActor
    func testBPOutOfRangeShowsAlert() throws {
        let app = makeApp()
        app.launch()

        navigateToTab(app: app, tabId: A11y.Tab.today, fallbackLabel: "Today")

        let bpRow = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", A11y.TodayRowPrefix.bp)).firstMatch
        XCTAssertTrue(waitForExistence(bpRow, timeout: 10), "A BP slot row should exist on Today")
        bpRow.tap()

        let systolicField = app.textFields[A11y.Field.systolic]
        XCTAssertTrue(waitForExistence(systolicField, timeout: 5), "Systolic field should exist")
        systolicField.clearAndTypeText("20")

        let diastolicField = app.textFields[A11y.Field.diastolic]
        XCTAssertTrue(waitForExistence(diastolicField, timeout: 5), "Diastolic field should exist")
        diastolicField.clearAndTypeText("20")

        let pulseField = app.textFields[A11y.Field.pulse]
        XCTAssertTrue(waitForExistence(pulseField, timeout: 5), "Pulse field should exist")
        pulseField.clearAndTypeText("20")

        let saveButton = firstExisting(in: [
            app.buttons[A11y.Action.save],
            app.navigationBars.buttons[A11y.Action.save],
            app.buttons["Save"]
        ])
        XCTAssertTrue(waitForExistence(saveButton, timeout: 5), "Save button should exist")
        saveButton.tap()

        let alert = app.alerts["Unusual values"]
        XCTAssertTrue(waitForExistence(alert, timeout: 5), "Unusual values alert should appear")
        alert.buttons["Cancel"].tap()

        let cancelButton = firstExisting(in: [
            app.buttons[A11y.Action.cancel],
            app.navigationBars.buttons["Cancel"],
            app.buttons["Cancel"]
        ])
        XCTAssertTrue(waitForExistence(cancelButton, timeout: 5), "Cancel button should exist")
        cancelButton.tap()
    }

    @MainActor
    func testGlucoseOutOfRangeShowsAlertAndInlineMessage() throws {
        let app = makeApp()
        app.launch()

        navigateToTab(app: app, tabId: A11y.Tab.today, fallbackLabel: "Today")

        let glucoseRow = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", A11y.TodayRowPrefix.glucose)).firstMatch
        XCTAssertTrue(waitForExistence(glucoseRow, timeout: 10), "A Glucose slot row should exist on Today")
        glucoseRow.tap()

        let glucoseField = app.textFields[A11y.Field.glucose]
        XCTAssertTrue(waitForExistence(glucoseField, timeout: 5), "Glucose value field should exist")
        glucoseField.clearAndTypeText("1")

        let saveButton = firstExisting(in: [
            app.buttons[A11y.Action.save],
            app.navigationBars.buttons[A11y.Action.save],
            app.buttons["Save"]
        ])
        XCTAssertTrue(waitForExistence(saveButton, timeout: 5), "Save button should exist")
        saveButton.tap()

        let alert = app.alerts["Unusual values"]
        XCTAssertTrue(waitForExistence(alert, timeout: 5), "Unusual values alert should appear")
        alert.buttons["Cancel"].tap()

        let inlineWarning = app.staticTexts["quickEntry.glucose.validationMessage"]
        XCTAssertTrue(waitForExistence(inlineWarning, timeout: 5), "Inline range warning should appear")

        let cancelButton = firstExisting(in: [
            app.buttons[A11y.Action.cancel],
            app.navigationBars.buttons["Cancel"],
            app.buttons["Cancel"]
        ])
        XCTAssertTrue(waitForExistence(cancelButton, timeout: 5), "Cancel button should exist")
        cancelButton.tap()
    }

    @MainActor
    func testBedtimeSlotToggleAffectsToday() throws {
        let app = makeApp()
        app.launch()

        navigateToTab(app: app, tabId: A11y.Tab.settings, fallbackLabel: "Settings")
        XCTAssertTrue(waitForExistence(app.navigationBars["Settings"], timeout: 5), "Settings screen should be visible")
        _ = waitForExistence(app.scrollViews["settings.scroll"], timeout: 5)

        let bedtimeToggle = app.switches[A11y.Settings.bedtimeSlotEnabled]
        scrollToElement(bedtimeToggle, in: app)
        XCTAssertTrue(waitForExistence(bedtimeToggle, timeout: 10), "Bedtime slot toggle should exist")

        if (bedtimeToggle.value as? String) == "1" {
            bedtimeToggle.tap()
        }

        tapSaveIfPresent(app: app)
        navigateToTab(app: app, tabId: A11y.Tab.today, fallbackLabel: "Today")
        _ = waitForExistence(app.navigationBars["Today"], timeout: 5)
        _ = waitForExistence(app.scrollViews["today.scroll"], timeout: 5)
        waitForTodayRows(app: app)

        let bedtimeRow = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Bedtime")).firstMatch
        scrollToElement(bedtimeRow, in: app, maxSwipes: 8)
        XCTAssertTrue(waitForNonExistence(bedtimeRow, timeout: 5), "Bedtime slot should not appear when disabled")

        navigateToTab(app: app, tabId: A11y.Tab.settings, fallbackLabel: "Settings")
        scrollToElement(bedtimeToggle, in: app)
        if (bedtimeToggle.value as? String) == "0" {
            bedtimeToggle.tap()
        }

        tapSaveIfPresent(app: app)
        navigateToTab(app: app, tabId: A11y.Tab.today, fallbackLabel: "Today")
        _ = waitForExistence(app.navigationBars["Today"], timeout: 5)
        _ = waitForExistence(app.scrollViews["today.scroll"], timeout: 5)
        waitForTodayRows(app: app)

        scrollToElement(bedtimeRow, in: app, maxSwipes: 8)
        XCTAssertTrue(waitForExistence(bedtimeRow, timeout: 10), "Bedtime slot should appear when enabled")

        // Cleanup: disable again to avoid affecting other tests
        navigateToTab(app: app, tabId: A11y.Tab.settings, fallbackLabel: "Settings")
        scrollToElement(bedtimeToggle, in: app)
        if (bedtimeToggle.value as? String) == "1" {
            bedtimeToggle.tap()
        }
        tapSaveIfPresent(app: app)
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

    @MainActor private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("UITESTING")
        return app
    }

    @MainActor
    private func dismissUnusualValuesAlertIfPresent(app: XCUIApplication) {
        let alert = app.alerts["Unusual values"]
        guard waitForExistence(alert, timeout: 2) else { return }
        let saveAnyway = alert.buttons["Save anyway"]
        if saveAnyway.exists {
            saveAnyway.tap()
            return
        }
        let ok = alert.buttons["OK"]
        if ok.exists {
            ok.tap()
            return
        }
    }

    @MainActor
    private func navigateToTab(app: XCUIApplication, tabId: String, fallbackLabel: String) {
        let tabBar = app.tabBars.firstMatch
        if waitForExistence(tabBar, timeout: 3) {
            let tabButton = tabBar.buttons[tabId].firstMatch
            if waitForExistence(tabButton, timeout: 2) {
                tabButton.tap()
                waitForScreen(app: app, label: fallbackLabel)
                return
            }
            let fallbackButton = tabBar.buttons[fallbackLabel].firstMatch
            if waitForExistence(fallbackButton, timeout: 2) {
                fallbackButton.tap()
                waitForScreen(app: app, label: fallbackLabel)
                return
            }
        }
        let anyButton = app.buttons[fallbackLabel].firstMatch
        if waitForExistence(anyButton, timeout: 2) {
            anyButton.tap()
            waitForScreen(app: app, label: fallbackLabel)
            return
        }
        let sidebarCell = app.cells[fallbackLabel].firstMatch
        if waitForExistence(sidebarCell, timeout: 2) {
            sidebarCell.tap()
            waitForScreen(app: app, label: fallbackLabel)
        }
    }

    @MainActor
    private func waitForScreen(app: XCUIApplication, label: String) {
        switch label {
        case "Today":
            _ = waitForExistence(app.scrollViews["today.scroll"], timeout: 5)
        case "Settings":
            _ = waitForExistence(app.scrollViews["settings.scroll"], timeout: 5)
        case "History":
            if !waitForExistence(app.scrollViews["history.scroll"], timeout: 3) {
                _ = waitForExistence(app.otherElements["history.list"], timeout: 7)
            }
        default:
            break
        }
    }

    @MainActor
    private func scrollToElement(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 6) {
        var swipes = 0
        while !element.isHittable && swipes < maxSwipes {
            if app.scrollViews["settings.scroll"].exists {
                app.scrollViews["settings.scroll"].swipeUp()
            } else if app.scrollViews["today.scroll"].exists {
                app.scrollViews["today.scroll"].swipeUp()
            } else if app.scrollViews["history.scroll"].exists {
                app.scrollViews["history.scroll"].swipeUp()
            } else if app.scrollViews.firstMatch.exists {
                app.scrollViews.firstMatch.swipeUp()
            } else {
                app.swipeUp()
            }
            swipes += 1
        }
    }

    @MainActor
    private func tapSaveIfPresent(app: XCUIApplication) {
        let saveButton = firstExisting(in: [
            app.buttons["settings.save"],
            app.navigationBars.buttons["Save"],
            app.buttons["Save"]
        ])
        if saveButton.exists {
            saveButton.tap()
        }
    }

    @MainActor
    private func ensureBPSlotExists(app: XCUIApplication) {
        let bpRow = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", A11y.TodayRowPrefix.bp)).firstMatch
        if waitForExistence(bpRow, timeout: 5) { return }

        navigateToTab(app: app, tabId: A11y.Tab.settings, fallbackLabel: "Settings")
        _ = waitForExistence(app.navigationBars["Settings"], timeout: 5)
        _ = waitForExistence(app.scrollViews["settings.scroll"], timeout: 5)
        let addTimeButton = app.buttons["Add time"]
        scrollToElement(addTimeButton, in: app)
        XCTAssertTrue(waitForExistence(addTimeButton, timeout: 5), "Add time button should exist in Settings")
        addTimeButton.tap()
        tapSaveIfPresent(app: app)

        navigateToTab(app: app, tabId: A11y.Tab.today, fallbackLabel: "Today")
    }

    @MainActor
    private func ensureGlucoseSlotExists(app: XCUIApplication) {
        let glucoseRow = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", A11y.TodayRowPrefix.glucose)).firstMatch
        if waitForExistence(glucoseRow, timeout: 5) { return }

        navigateToTab(app: app, tabId: A11y.Tab.settings, fallbackLabel: "Settings")
        _ = waitForExistence(app.navigationBars["Settings"], timeout: 5)
        _ = waitForExistence(app.scrollViews["settings.scroll"], timeout: 5)
        let beforeMealToggle = app.switches[A11y.Settings.glucoseBeforeMeal]
        scrollToElement(beforeMealToggle, in: app)
        XCTAssertTrue(waitForExistence(beforeMealToggle, timeout: 10), "Before meal toggle should exist in Settings")
        if (beforeMealToggle.value as? String) == "0" {
            beforeMealToggle.tap()
        }
        tapSaveIfPresent(app: app)

        navigateToTab(app: app, tabId: A11y.Tab.today, fallbackLabel: "Today")
    }

    @MainActor
    private func waitForTodayRows(app: XCUIApplication) {
        _ = waitForExistence(app.scrollViews["today.scroll"], timeout: 5)
        let anyRow = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "today.row.")).firstMatch
        _ = waitForExistence(anyRow, timeout: 10)
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

