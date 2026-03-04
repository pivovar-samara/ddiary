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
            static let debug = "tab.debug" // fallback to label "Debug"
        }
        enum TodayRowPrefix {
            static let bp = "today.row.bp."
            static let glucose = "today.row.glucose."
            static let glucoseBedtime = "today.row.glucose.bedtime."
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
            static let dailyCycleMode = "settings.glucose.dailyCycle"
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
            if waitForExistence(todayButton, timeout: 8) { todayButton.tap() }
        }
        _ = waitForExistence(app.scrollViews["today.scroll"], timeout: 8)

        // 3) Open BP Quick Entry by tapping a Today BP row and enter values
        ensureBPSlotExists(app: app)
        let bpRow = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", A11y.TodayRowPrefix.bp)).firstMatch
        XCTAssertTrue(waitForExistence(bpRow, timeout: 10), "A BP slot row should exist on Today")
        bpRow.tap()

        let systolicField = app.textFields[A11y.Field.systolic]
        XCTAssertTrue(waitForExistence(systolicField, timeout: 8), "Systolic field should exist")
        systolicField.clearAndTypeText("120")

        let diastolicField = app.textFields[A11y.Field.diastolic]
        XCTAssertTrue(waitForExistence(diastolicField, timeout: 8), "Diastolic field should exist")
        diastolicField.clearAndTypeText("80")

        let pulseField = app.textFields[A11y.Field.pulse]
        XCTAssertTrue(waitForExistence(pulseField, timeout: 8), "Pulse field should exist")
        pulseField.clearAndTypeText("72")

        let bpSaveButton = firstExisting(in: [
            app.buttons[A11y.Action.save],
            app.navigationBars.buttons[A11y.Action.save],
            app.buttons["Save"]
        ])
        XCTAssertTrue(waitForExistence(bpSaveButton, timeout: 8), "Save button should exist on BP Quick Entry")
        bpSaveButton.tap()
        _ = waitForNonExistence(systolicField, timeout: 8)

        // 4) Open Glucose Quick Entry by tapping a Today Glucose row and enter values
        ensureGlucoseSlotExists(app: app)
        let glucoseRow = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", A11y.TodayRowPrefix.glucose)).firstMatch
        XCTAssertTrue(waitForExistence(glucoseRow, timeout: 10), "A Glucose slot row should exist on Today")
        glucoseRow.tap()

        let glucoseField = app.textFields[A11y.Field.glucose]
        XCTAssertTrue(waitForExistence(glucoseField, timeout: 8), "Glucose value field should exist")
        // Enter a value that matches the current unit to avoid out-of-range warnings
        let unitLabel = app.staticTexts["quickEntry.glucose.unitLabel"]
        XCTAssertTrue(waitForExistence(unitLabel, timeout: 8), "Glucose unit label should exist")
        let unitText = unitLabel.label.lowercased()
        let glucoseValue = unitText.contains("mg/dl") ? "100" : "6"
        glucoseField.clearAndTypeText(glucoseValue)

        let glucoseSaveButton = firstExisting(in: [
            app.buttons[A11y.Action.save],
            app.navigationBars.buttons[A11y.Action.save],
            app.buttons["Save"]
        ])
        XCTAssertTrue(waitForExistence(glucoseSaveButton, timeout: 8), "Save button should exist on Glucose Quick Entry")
        glucoseSaveButton.tap()
        dismissUnusualValuesAlertIfPresent(app: app)
        _ = waitForNonExistence(glucoseField, timeout: 8)

        // 5) Navigate to History (robust helper waits for screen)
        navigateToTab(app: app, tabId: A11y.Tab.history, fallbackLabel: "History")
        let historyList = app.otherElements["history.list"]
        let historyScroll = app.scrollViews["history.scroll"]
        XCTAssertTrue(waitForExistence(historyList, timeout: 10) || waitForExistence(historyScroll, timeout: 10), "History list should be visible")

        // 6) Verify at least one BP and one Glucose entry appear in History using stable row identifiers
        let bpHistoryRow = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "history.row.bp.")).firstMatch
        scrollToElement(bpHistoryRow, in: app, maxSwipes: 3)
        var bpFound = waitForExistence(bpHistoryRow, timeout: 10)
        if !bpFound {
            // Fallback to badge text if row identifiers are not available yet
            let bpBadge = app.staticTexts["BP"].firstMatch
            scrollToElement(bpBadge, in: app, maxSwipes: 3)
            bpFound = waitForExistence(bpBadge, timeout: 8)
        }
        XCTAssertTrue(bpFound, "Expected at least one BP entry in History")

        let gluHistoryRow = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "history.row.glucose.")).firstMatch
        scrollToElement(gluHistoryRow, in: app, maxSwipes: 3)
        var gluFound = waitForExistence(gluHistoryRow, timeout: 10)
        if !gluFound {
            let gluBadge = app.staticTexts["GLU"].firstMatch
            scrollToElement(gluBadge, in: app, maxSwipes: 3)
            gluFound = waitForExistence(gluBadge, timeout: 8)
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
    func testDebugTabVisibilityMatchesBuildConfiguration() throws {
        let app = makeApp()
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(waitForExistence(tabBar, timeout: 8), "Tab bar should be visible")

        let debugById = tabBar.buttons[A11y.Tab.debug].firstMatch
        let debugByLabel = tabBar.buttons["Debug"].firstMatch

        #if DEBUG
        let isVisibleInDebug = waitForExistence(debugById, timeout: 2) || waitForExistence(debugByLabel, timeout: 2)
        XCTAssertTrue(isVisibleInDebug, "Debug tab should be visible in Debug builds")
        #else
        XCTAssertTrue(waitForNonExistence(debugById, timeout: 2), "Debug tab should be hidden in Production builds")
        XCTAssertTrue(waitForNonExistence(debugByLabel, timeout: 2), "Debug tab should be hidden in Production builds")
        #endif
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
        XCTAssertTrue(waitForExistence(systolicField, timeout: 8), "Systolic field should exist")
        systolicField.clearAndTypeText("20")

        let diastolicField = app.textFields[A11y.Field.diastolic]
        XCTAssertTrue(waitForExistence(diastolicField, timeout: 8), "Diastolic field should exist")
        diastolicField.clearAndTypeText("20")

        let pulseField = app.textFields[A11y.Field.pulse]
        XCTAssertTrue(waitForExistence(pulseField, timeout: 8), "Pulse field should exist")
        pulseField.clearAndTypeText("20")

        let saveButton = firstExisting(in: [
            app.buttons[A11y.Action.save],
            app.navigationBars.buttons[A11y.Action.save],
            app.buttons["Save"]
        ])
        XCTAssertTrue(waitForExistence(saveButton, timeout: 8), "Save button should exist")
        saveButton.tap()

        let alert = app.alerts["Unusual values"]
        XCTAssertTrue(waitForExistence(alert, timeout: 8), "Unusual values alert should appear")
        alert.buttons["Cancel"].tap()

        let cancelButton = firstExisting(in: [
            app.buttons[A11y.Action.cancel],
            app.navigationBars.buttons["Cancel"],
            app.buttons["Cancel"]
        ])
        XCTAssertTrue(waitForExistence(cancelButton, timeout: 8), "Cancel button should exist")
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
        XCTAssertTrue(waitForExistence(glucoseField, timeout: 8), "Glucose value field should exist")
        glucoseField.clearAndTypeText("1")

        let saveButton = firstExisting(in: [
            app.buttons[A11y.Action.save],
            app.navigationBars.buttons[A11y.Action.save],
            app.buttons["Save"]
        ])
        XCTAssertTrue(waitForExistence(saveButton, timeout: 8), "Save button should exist")
        saveButton.tap()

        let alert = app.alerts["Unusual values"]
        XCTAssertTrue(waitForExistence(alert, timeout: 8), "Unusual values alert should appear")
        alert.buttons["Cancel"].tap()

        let inlineWarning = app.staticTexts["quickEntry.glucose.validationMessage"]
        XCTAssertTrue(waitForExistence(inlineWarning, timeout: 8), "Inline range warning should appear")

        let cancelButton = firstExisting(in: [
            app.buttons[A11y.Action.cancel],
            app.navigationBars.buttons["Cancel"],
            app.buttons["Cancel"]
        ])
        XCTAssertTrue(waitForExistence(cancelButton, timeout: 8), "Cancel button should exist")
        cancelButton.tap()
    }

    @MainActor
    func testBedtimeSlotToggleAffectsToday() throws {
        let app = makeApp()
        app.launch()

        navigateToTab(app: app, tabId: A11y.Tab.settings, fallbackLabel: "Settings")
        XCTAssertTrue(waitForExistence(app.navigationBars["Settings"], timeout: 8), "Settings screen should be visible")
        _ = waitForExistence(settingsContainer(in: app), timeout: 8)

        let bedtimeToggle = app.switches[A11y.Settings.bedtimeSlotEnabled]
        scrollToElement(bedtimeToggle, in: app)
        XCTAssertTrue(waitForExistence(bedtimeToggle, timeout: 10), "Bedtime slot toggle should exist")

        // Keep this test deterministic: bedtime visibility on Today is unconditional only in non-cycle mode.
        let dailyCycleToggle = app.switches[A11y.Settings.dailyCycleMode]
        scrollToElement(dailyCycleToggle, in: app)
        if waitForExistence(dailyCycleToggle, timeout: 5) {
            XCTAssertTrue(setSwitch(dailyCycleToggle, on: false), "Daily cycle mode should be disabled for this test")
        }

        scrollToElement(bedtimeToggle, in: app)
        XCTAssertTrue(waitForExistence(bedtimeToggle, timeout: 5), "Bedtime slot toggle should still be reachable")
        XCTAssertTrue(setSwitch(bedtimeToggle, on: false), "Bedtime slot toggle should be disabled before verification")

        waitForAutosaveDebounce()
        tapSaveIfPresent(app: app)
        navigateToTab(app: app, tabId: A11y.Tab.today, fallbackLabel: "Today")
        _ = waitForExistence(app.navigationBars["Today"], timeout: 8)
        _ = waitForExistence(app.scrollViews["today.scroll"], timeout: 8)
        waitForTodayRows(app: app)

        let bedtimeRowWhenDisabled = bedtimeRow(in: app)
        scrollToTop(in: app)
        scrollToElement(bedtimeRowWhenDisabled, in: app, maxSwipes: 4)
        XCTAssertTrue(waitForNonExistence(bedtimeRowWhenDisabled, timeout: 8), "Bedtime slot should not appear when disabled")

        navigateToTab(app: app, tabId: A11y.Tab.settings, fallbackLabel: "Settings")
        scrollToElement(bedtimeToggle, in: app)
        XCTAssertTrue(waitForExistence(bedtimeToggle, timeout: 5), "Bedtime slot toggle should exist in Settings")
        XCTAssertTrue(setSwitch(bedtimeToggle, on: true), "Bedtime slot toggle should be enabled")

        waitForAutosaveDebounce()
        tapSaveIfPresent(app: app)
        navigateToTab(app: app, tabId: A11y.Tab.today, fallbackLabel: "Today")
        _ = waitForExistence(app.navigationBars["Today"], timeout: 8)
        _ = waitForExistence(app.scrollViews["today.scroll"], timeout: 8)
        waitForTodayRows(app: app)

        let bedtimeRowWhenEnabled = bedtimeRow(in: app)
        scrollToTop(in: app)
        scrollToElement(bedtimeRowWhenEnabled, in: app, maxSwipes: 4)
        if !bedtimeRowWhenEnabled.exists {
            expandCompletedSectionIfPresent(app: app)
            scrollToElement(bedtimeRowWhenEnabled, in: app, maxSwipes: 4)
        }
        XCTAssertTrue(waitForExistence(bedtimeRowWhenEnabled, timeout: 10), "Bedtime slot should appear when enabled")

        // Cleanup: disable again to avoid affecting other tests
        navigateToTab(app: app, tabId: A11y.Tab.settings, fallbackLabel: "Settings")
        scrollToElement(bedtimeToggle, in: app)
        _ = setSwitch(bedtimeToggle, on: false)
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
        if waitForExistence(tabBar, timeout: 8) {
            let tabButton = tabBar.buttons[tabId].firstMatch
            if tabButton.exists || waitForExistence(tabButton, timeout: 1) {
                tabButton.tap()
                waitForScreen(app: app, label: fallbackLabel)
                return
            }
            let fallbackButton = tabBar.buttons[fallbackLabel].firstMatch
            if fallbackButton.exists || waitForExistence(fallbackButton, timeout: 1) {
                fallbackButton.tap()
                waitForScreen(app: app, label: fallbackLabel)
                return
            }
        }
        let anyButton = app.buttons[fallbackLabel].firstMatch
        if waitForExistence(anyButton, timeout: 8) {
            anyButton.tap()
            waitForScreen(app: app, label: fallbackLabel)
            return
        }
        let sidebarCell = app.cells[fallbackLabel].firstMatch
        if waitForExistence(sidebarCell, timeout: 8) {
            sidebarCell.tap()
            waitForScreen(app: app, label: fallbackLabel)
        }
    }

    @MainActor
    private func waitForScreen(app: XCUIApplication, label: String) {
        switch label {
        case "Today":
            _ = waitForExistence(app.scrollViews["today.scroll"], timeout: 8)
        case "Settings":
            _ = waitForExistence(settingsContainer(in: app), timeout: 8)
        case "History":
            if !waitForExistence(app.scrollViews["history.scroll"], timeout: 8) {
                _ = waitForExistence(app.otherElements["history.list"], timeout: 8)
            }
        default:
            break
        }
    }

    @MainActor
    private func scrollToElement(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 3) {
        let scrollContainer = scrollContainer(in: app)

        var swipes = 0
        while !element.isHittable && swipes < maxSwipes {
            if scrollContainer.exists {
                scrollContainer.swipeUp()
            } else {
                app.swipeUp()
            }
            swipes += 1
        }

        swipes = 0
        while !element.isHittable && swipes < maxSwipes {
            if scrollContainer.exists {
                scrollContainer.swipeDown()
            } else {
                app.swipeDown()
            }
            swipes += 1
        }
    }

    @MainActor
    private func scrollToTop(in app: XCUIApplication, maxSwipes: Int = 8) {
        let scrollContainer = scrollContainer(in: app)

        for _ in 0..<maxSwipes {
            if scrollContainer.exists {
                scrollContainer.swipeDown()
            } else {
                app.swipeDown()
            }
        }
    }

    private func waitForAutosaveDebounce() {
        let expectation = XCTestExpectation(description: "Wait for settings autosave debounce")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            expectation.fulfill()
        }
        _ = XCTWaiter.wait(for: [expectation], timeout: 2.0)
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
        if waitForExistence(bpRow, timeout: 8) { return }

        navigateToTab(app: app, tabId: A11y.Tab.settings, fallbackLabel: "Settings")
        _ = waitForExistence(app.navigationBars["Settings"], timeout: 8)
        _ = waitForExistence(settingsContainer(in: app), timeout: 8)
        let addTimeButton = app.buttons["Add time"]
        scrollToElement(addTimeButton, in: app)
        XCTAssertTrue(waitForExistence(addTimeButton, timeout: 8), "Add time button should exist in Settings")
        addTimeButton.tap()
        tapSaveIfPresent(app: app)

        navigateToTab(app: app, tabId: A11y.Tab.today, fallbackLabel: "Today")
    }

    @MainActor
    private func ensureGlucoseSlotExists(app: XCUIApplication) {
        let glucoseRow = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", A11y.TodayRowPrefix.glucose)).firstMatch
        if waitForExistence(glucoseRow, timeout: 8) { return }

        navigateToTab(app: app, tabId: A11y.Tab.settings, fallbackLabel: "Settings")
        _ = waitForExistence(app.navigationBars["Settings"], timeout: 8)
        _ = waitForExistence(settingsContainer(in: app), timeout: 8)
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
        _ = waitForExistence(app.scrollViews["today.scroll"], timeout: 8)
        let anyRow = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "today.row.")).firstMatch
        _ = waitForExistence(anyRow, timeout: 10)
    }

    @MainActor
    private func bedtimeRow(in app: XCUIApplication) -> XCUIElement {
        let predicate = NSPredicate(format: "identifier BEGINSWITH %@", A11y.TodayRowPrefix.glucoseBedtime)
        return app.buttons.matching(predicate).firstMatch
    }

    @MainActor
    private func switchValueIsOn(_ toggle: XCUIElement) -> Bool? {
        guard let rawValue = toggle.value as? String else { return nil }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value == "1" || value == "on" || value == "true" { return true }
        if value == "0" || value == "off" || value == "false" { return false }
        return nil
    }

    @MainActor
    private func waitForSwitchState(_ toggle: XCUIElement, isOn: Bool, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let current = switchValueIsOn(toggle), current == isOn {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        return false
    }

    @MainActor
    @discardableResult
    private func setSwitch(_ toggle: XCUIElement, on shouldBeOn: Bool, timeout: TimeInterval = 5) -> Bool {
        guard waitForExistence(toggle, timeout: timeout) else { return false }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if waitForSwitchState(toggle, isOn: shouldBeOn, timeout: 0.3) {
                return true
            }

            toggle.tap()
            if waitForSwitchState(toggle, isOn: shouldBeOn, timeout: 0.3) {
                return true
            }

            // Some wrapped SwiftUI Toggle rows may require tapping near the trailing switch control.
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
            if waitForSwitchState(toggle, isOn: shouldBeOn, timeout: 0.3) {
                return true
            }
        }

        return false
    }

    @MainActor
    private func settingsContainer(in app: XCUIApplication) -> XCUIElement {
        let settingsCollection = app.collectionViews["settings.scroll"]
        if settingsCollection.exists { return settingsCollection }
        let settingsScroll = app.scrollViews["settings.scroll"]
        if settingsScroll.exists { return settingsScroll }
        return app.otherElements["settings.scroll"].firstMatch
    }

    @MainActor
    private func scrollContainer(in app: XCUIApplication) -> XCUIElement {
        if app.scrollViews["today.scroll"].exists {
            return app.scrollViews["today.scroll"]
        }
        if app.scrollViews["history.scroll"].exists {
            return app.scrollViews["history.scroll"]
        }
        let settings = settingsContainer(in: app)
        if settings.exists {
            return settings
        }
        return app.scrollViews.firstMatch
    }

    @MainActor
    private func expandCompletedSectionIfPresent(app: XCUIApplication) {
        let disclosure = app.otherElements[A11y.Today.completedDisclosure].firstMatch
        if disclosure.exists {
            disclosure.tap()
            return
        }
        let button = app.buttons[A11y.Today.completedDisclosure].firstMatch
        if button.exists {
            button.tap()
        }
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
