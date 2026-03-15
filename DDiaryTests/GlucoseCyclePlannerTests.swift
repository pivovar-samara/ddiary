import XCTest
@testable import DDiary

final class GlucoseCyclePlannerTests: XCTestCase {

    // MARK: - dateKey

    func test_dateKey_formatsYyyyMmDd() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let date = cal.date(from: DateComponents(year: 2026, month: 3, day: 5))!
        XCTAssertEqual(GlucoseCyclePlanner.dateKey(for: date, calendar: cal), "2026-03-05")
    }

    func test_dateKey_padsSingleDigitMonthAndDay() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let date = cal.date(from: DateComponents(year: 2026, month: 1, day: 9))!
        XCTAssertEqual(GlucoseCyclePlanner.dateKey(for: date, calendar: cal), "2026-01-09")
    }

    func test_dateKey_respectsCalendarTimeZone() {
        // A UTC midnight instant is still "previous day" in UTC-5.
        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = TimeZone(identifier: "UTC")!
        var estCal = Calendar(identifier: .gregorian)
        estCal.timeZone = TimeZone(identifier: "America/New_York")!

        // 2026-03-06 00:00:00 UTC == 2026-03-05 19:00:00 EST
        let utcMidnight = utcCal.date(from: DateComponents(year: 2026, month: 3, day: 6,
                                                            hour: 0, minute: 0, second: 0))!

        XCTAssertEqual(GlucoseCyclePlanner.dateKey(for: utcMidnight, calendar: utcCal), "2026-03-06")
        XCTAssertEqual(GlucoseCyclePlanner.dateKey(for: utcMidnight, calendar: estCal), "2026-03-05")
    }

    func test_dateKey_producesDistinctKeyForEachDay() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let jan1 = cal.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let jan2 = cal.date(from: DateComponents(year: 2026, month: 1, day: 2))!
        XCTAssertNotEqual(
            GlucoseCyclePlanner.dateKey(for: jan1, calendar: cal),
            GlucoseCyclePlanner.dateKey(for: jan2, calendar: cal)
        )
    }

    // MARK: - pruneOverrides – retention window

    func test_pruneOverrides_keepsEntriesOnOrAfterCutoff() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let today = cal.date(from: DateComponents(year: 2026, month: 3, day: 15))!

        // cutoff = today - 30 days = 2026-02-13
        let onCutoff = "2026-02-13"   // exactly at cutoff – keep
        let beforeCutoff = "2026-02-12" // one day before cutoff – drop

        let overrides: [String: Int] = [
            onCutoff: 1,
            beforeCutoff: 2,
            "2026-03-15": 0,  // today – keep
        ]

        let result = GlucoseCyclePlanner.pruneOverrides(overrides, today: today,
                                                         keepingDays: 30, calendar: cal)

        XCTAssertNotNil(result[onCutoff], "Entry on cutoff date should be retained")
        XCTAssertNil(result[beforeCutoff], "Entry before cutoff date should be dropped")
        XCTAssertNotNil(result["2026-03-15"], "Today's entry should be retained")
    }

    func test_pruneOverrides_dropsAllEntriesOlderThanWindow() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let today = cal.date(from: DateComponents(year: 2026, month: 3, day: 15))!

        let overrides: [String: Int] = [
            "2025-01-01": 0,
            "2025-06-30": 1,
        ]

        let result = GlucoseCyclePlanner.pruneOverrides(overrides, today: today,
                                                         keepingDays: 30, calendar: cal)
        XCTAssertTrue(result.isEmpty, "All stale entries should be removed")
    }

    func test_pruneOverrides_dropsInvalidKeysSilently() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let today = cal.date(from: DateComponents(year: 2026, month: 3, day: 15))!

        let overrides: [String: Int] = [
            "not-a-date": 1,
            "2026-99-99": 2,
            "2026-03-15": 0,  // valid – keep
        ]

        let result = GlucoseCyclePlanner.pruneOverrides(overrides, today: today,
                                                         keepingDays: 30, calendar: cal)
        XCTAssertNil(result["not-a-date"], "Invalid key should be dropped")
        XCTAssertNil(result["2026-99-99"], "Malformed key should be dropped")
        XCTAssertNotNil(result["2026-03-15"], "Valid recent key should be retained")
    }

    func test_pruneOverrides_cutoffUsesCalendarTimeZone() {
        // In UTC+14 (Line Islands) 2026-02-13 00:00 UTC is already 2026-02-13 14:00 local time,
        // while in UTC-12 it's still 2026-02-12. Use a timezone that makes "today" land on a
        // different calendar day and verify the cutoff is computed relative to that local today.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Pacific/Kiritimati")! // UTC+14

        // "today" as seen in UTC+14: 2026-03-15 local
        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = TimeZone(identifier: "UTC")!
        let today = utcCal.date(from: DateComponents(year: 2026, month: 3, day: 15,
                                                      hour: 0, minute: 0))!
        // cutoff in UTC+14: startOfDay(today) – 30 days
        // startOfDay("2026-03-15 14:00 local") = "2026-03-15 00:00 local" = "2026-03-14 10:00 UTC"
        // cutoff = startOfDay(today+14) – 30 days = "2026-02-13 00:00 local"
        let keepKey = GlucoseCyclePlanner.dateKey(
            for: cal.date(from: DateComponents(year: 2026, month: 2, day: 13))!,
            calendar: cal
        )
        let dropKey = GlucoseCyclePlanner.dateKey(
            for: cal.date(from: DateComponents(year: 2026, month: 2, day: 12))!,
            calendar: cal
        )
        let overrides: [String: Int] = [keepKey: 1, dropKey: 2]

        let result = GlucoseCyclePlanner.pruneOverrides(overrides, today: today,
                                                         keepingDays: 30, calendar: cal)
        XCTAssertNotNil(result[keepKey], "Entry on cutoff boundary should be retained")
        XCTAssertNil(result[dropKey], "Entry before cutoff should be dropped")
    }

    func test_pruneOverrides_customKeepingDays() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let today = cal.date(from: DateComponents(year: 2026, month: 3, day: 15))!

        // With keepingDays: 7, cutoff = 2026-03-08
        let overrides: [String: Int] = [
            "2026-03-08": 1,   // on cutoff – keep
            "2026-03-07": 2,   // one day before – drop
            "2026-03-15": 0,   // today – keep
        ]

        let result = GlucoseCyclePlanner.pruneOverrides(overrides, today: today,
                                                         keepingDays: 7, calendar: cal)
        XCTAssertNotNil(result["2026-03-08"])
        XCTAssertNil(result["2026-03-07"])
        XCTAssertNotNil(result["2026-03-15"])
    }
}
