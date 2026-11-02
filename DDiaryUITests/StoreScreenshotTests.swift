import XCTest

/// Captures App Store screenshots for every shipped localization.
///
/// Runs only when `SHOT_DIR` is set (pass `TEST_RUNNER_SHOT_DIR=/abs/path` to xcodebuild);
/// `SHOT_LOCALES` optionally narrows the run, e.g. `en,ru`; `SHOT_DEVICE` picks the screen set
/// (`iphone`, `duo` or `ipad`, default `iphone`). Files land in `<SHOT_DIR>/<locale>/<n>_<screen>.png`.
final class StoreScreenshotTests: XCTestCase {
    private static let locales: [(language: String, locale: String)] = [
        ("en", "en_US"), ("ru", "ru_RU"), ("es", "es_ES"), ("it", "it_IT"),
        ("fr", "fr_FR"), ("de", "de_DE"), ("pt-BR", "pt_BR"), ("tr", "tr_TR"),
        ("pl", "pl_PL"), ("nl", "nl_NL"), ("uk", "uk_UA"), ("sv", "sv_SE"),
        ("ko", "ko_KR"), ("ja", "ja_JP"), ("zh-Hans", "zh_CN"), ("ar", "ar_SA"),
    ]

    private var rightToLeft = false

    @MainActor
    func testCaptureStoreScreenshots() throws {
        let env = ProcessInfo.processInfo.environment
        guard let shotDir = env["SHOT_DIR"] else {
            throw XCTSkip("SHOT_DIR is not set")
        }
        let device = env["SHOT_DEVICE"] ?? "iphone"
        let wanted = env["SHOT_LOCALES"].map { Set($0.split(separator: ",").map(String.init)) }
        continueAfterFailure = false

        for entry in Self.locales where wanted?.contains(entry.language) ?? true {
            let dir = URL(fileURLWithPath: shotDir).appendingPathComponent(entry.language)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try capture(language: entry.language, locale: entry.locale, device: device, into: dir)
        }
    }

    @MainActor
    private func capture(language: String, locale: String, device: String, into dir: URL) throws {
        XCUIDevice.shared.orientation = device == "ipad" ? .landscapeLeft : .portrait
        rightToLeft = Locale.Language(identifier: language).characterDirection == .rightToLeft
        let app = XCUIApplication()
        app.launchArguments = [
            "PRETTY_DATA", "DEMO_TIME=11:10",
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", locale,
        ]
        app.launch()

        // 1. Today
        XCTAssertTrue(app.descendants(matching: .any)["today.scroll"].waitForExistence(timeout: 15))
        settle()
        try save(dir, "1_today")

        if device == "ipad" {
            app.descendants(matching: .any)["tab.history"].firstMatch.tap()
            XCTAssertTrue(app.descendants(matching: .any)["history.summary"].waitForExistence(timeout: 8))
            settle()
            try save(dir, "2_history")
            app.descendants(matching: .any)["tab.settings"].firstMatch.tap()
            XCTAssertTrue(app.descendants(matching: .any)["settings.meal.breakfast"].waitForExistence(timeout: 8))
            settle()
            try save(dir, "3_settings")
            app.terminate()
            return
        }
        // Points from the top of the screen where the scroll anchors sit, matching the existing shots.
        // The Duo has no navigation bar over the list, so its anchors put a section header at the top edge.
        let reminderAnchorY: CGFloat = device == "duo" ? 42 : 176
        let exportAnchorY: CGFloat = device == "duo" ? 262 : 446

        // 2. Blood pressure quick entry
        app.buttons["today.addMeasurement"].tap()
        let bpItem = app.buttons["today.addMeasurement.bp"]
        XCTAssertTrue(bpItem.waitForExistence(timeout: 5))
        bpItem.tap()
        let systolic = app.textFields["quickEntry.bp.systolicField"]
        XCTAssertTrue(systolic.waitForExistence(timeout: 8))
        // On a cold start the keyboard can swallow the first keystrokes, so check the field and retype.
        for _ in 0..<3 where (systolic.value as? String) != "118" {
            if (systolic.value(forKey: "hasKeyboardFocus") as? Bool) != true { systolic.tap() }
            _ = app.keyboards.firstMatch.waitForExistence(timeout: 5)
            settle(seconds: 0.8)
            app.typeText("118")
            app.typeText("75")
            app.typeText("63")
            settle()
        }
        XCTAssertEqual(systolic.value as? String, "118")
        try save(dir, "2_entry")
        app.buttons["quickEntry.cancel"].tap()
        XCTAssertTrue(app.buttons["today.addMeasurement"].waitForExistence(timeout: 8))

        // 3. History
        app.descendants(matching: .any)["tab.history"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["history.summary"].waitForExistence(timeout: 8))
        settle()
        try save(dir, "3_history")

        // 4. Settings: meal times and reminders
        app.descendants(matching: .any)["tab.settings"].firstMatch.tap()
        let breakfast = app.descendants(matching: .any)["settings.meal.breakfast"].firstMatch
        XCTAssertTrue(breakfast.waitForExistence(timeout: 8))
        scroll(app, anchor: breakfast, toY: reminderAnchorY)
        settle(seconds: 2.5)
        try save(dir, "4_reminders")

        // 5. Settings: Google Sheets backup and export
        let exportFrom = app.descendants(matching: .any)["settings.export.fromDate"].firstMatch
        for _ in 0..<8 where !exportFrom.exists || !exportFrom.isHittable {
            drag(app, by: 280)
        }
        scroll(app, anchor: exportFrom, toY: exportAnchorY)
        settle(seconds: 2.5)
        try save(dir, "5_google")

        app.terminate()
    }

    /// Drags the settings list without momentum until `anchor` sits at `toY` points.
    @MainActor
    private func scroll(_ app: XCUIApplication, anchor: XCUIElement, toY targetY: CGFloat) {
        for _ in 0..<20 {
            guard anchor.exists else { return }
            let delta = anchor.frame.minY - targetY
            if abs(delta) < 4 { break }
            // The scroll view eats the first ~10 points of a drag before it starts moving.
            let slop: CGFloat = abs(delta) < 40 ? (delta > 0 ? 10 : -10) : 0
            drag(app, by: max(-280, min(280, delta + slop)))
        }
    }

    /// Positive `distance` scrolls content up (reveals what is below).
    @MainActor
    private func drag(_ app: XCUIApplication, by distance: CGFloat) {
        // Start on the row labels, away from the steppers, pickers and toggles on the trailing side:
        // a drag that begins on one of those does not scroll the list.
        let x: CGFloat = rightToLeft ? 0.7 : 0.15
        let start = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: x, dy: 0.6))
        let end = start.withOffset(CGVector(dx: 0, dy: -distance))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.4)
    }

    private func settle(seconds: TimeInterval = 1.2) {
        Thread.sleep(forTimeInterval: seconds)
    }

    @MainActor
    private func save(_ dir: URL, _ name: String) throws {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try png.write(to: dir.appendingPathComponent("\(name).png"))
    }
}
