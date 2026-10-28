import XCTest
@testable import DDiary

@MainActor
final class DayBoundaryTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    func test_defaultRollover_logicalDayIsCalendarDay() throws {
        let sut = DayBoundary(rolloverMinutes: 0, calendar: calendar)

        XCTAssertEqual(sut.logicalDay(containing: try date(day: 17, hour: 0, minute: 30)), try date(day: 17, hour: 0, minute: 0))
        XCTAssertEqual(sut.logicalDay(containing: try date(day: 17, hour: 23, minute: 59)), try date(day: 17, hour: 0, minute: 0))
    }

    func test_beforeRollover_logicalDayIsPreviousDate() throws {
        let sut = DayBoundary(rolloverMinutes: 4 * 60, calendar: calendar)

        XCTAssertEqual(sut.logicalDay(containing: try date(day: 17, hour: 3, minute: 59)), try date(day: 16, hour: 0, minute: 0))
        XCTAssertEqual(sut.logicalDay(containing: try date(day: 17, hour: 4, minute: 0)), try date(day: 17, hour: 0, minute: 0))
    }

    func test_window_spansRolloverToRollover() throws {
        let sut = DayBoundary(rolloverMinutes: 4 * 60, calendar: calendar)

        let window = sut.window(for: try date(day: 16, hour: 0, minute: 0))

        XCTAssertEqual(window.start, try date(day: 16, hour: 4, minute: 0))
        XCTAssertEqual(window.end, try date(day: 17, hour: 4, minute: 0))
    }

    func test_slotDate_beforeRollover_movesToNextCalendarDate() throws {
        let sut = DayBoundary(rolloverMinutes: 4 * 60, calendar: calendar)
        let day = try date(day: 16, hour: 0, minute: 0)

        XCTAssertEqual(sut.slotDate(on: day, hour: 1, minute: 0), try date(day: 17, hour: 1, minute: 0))
        XCTAssertEqual(sut.slotDate(on: day, hour: 4, minute: 0), try date(day: 16, hour: 4, minute: 0))
        XCTAssertEqual(sut.slotDate(on: day, hour: 22, minute: 0), try date(day: 16, hour: 22, minute: 0))
    }

    func test_nextRollover_isStrictlyAfterDate() throws {
        let sut = DayBoundary(rolloverMinutes: 4 * 60, calendar: calendar)

        XCTAssertEqual(sut.nextRollover(after: try date(day: 17, hour: 2, minute: 0)), try date(day: 17, hour: 4, minute: 0))
        XCTAssertEqual(sut.nextRollover(after: try date(day: 17, hour: 4, minute: 0)), try date(day: 18, hour: 4, minute: 0))
    }

    func test_init_clampsOutOfRangeMinutes() {
        XCTAssertEqual(DayBoundary(rolloverMinutes: -10, calendar: calendar).rolloverMinutes, 0)
        XCTAssertEqual(DayBoundary(rolloverMinutes: 5000, calendar: calendar).rolloverMinutes, 23 * 60 + 59)
    }

    private func date(day: Int, hour: Int, minute: Int) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: day, hour: hour, minute: minute)))
    }
}
