import Foundation

/// Maps wall-clock time onto the "logical day" the Today screen shows.
///
/// The logical day starts at `rolloverMinutes` past midnight instead of at midnight, so with a
/// rollover of 04:00 the moment Tuesday 02:00 still belongs to Monday. A planned time earlier than
/// the rollover belongs to the tail of the logical day and lands on the next calendar date: a
/// 01:00 bedtime slot of Monday is Tuesday 01:00. With the default rollover of 0 every logical day
/// is exactly a calendar day.
public struct DayBoundary: Sendable, Equatable {
    public let rolloverMinutes: Int
    public let calendar: Calendar

    public init(rolloverMinutes: Int, calendar: Calendar = .current) {
        self.rolloverMinutes = Self.clamped(rolloverMinutes)
        self.calendar = calendar
    }

    init(settings: UserSettings, calendar: Calendar = .current) {
        self.init(rolloverMinutes: settings.dayRolloverMinutes, calendar: calendar)
    }

    /// Start of the calendar day that names the logical day containing `date`.
    public func logicalDay(containing date: Date) -> Date {
        let shifted = calendar.date(byAdding: .minute, value: -rolloverMinutes, to: date) ?? date
        return calendar.startOfDay(for: shifted)
    }

    /// The half-open interval `[start, end)` of wall-clock time that belongs to `logicalDay`.
    public func window(for logicalDay: Date) -> (start: Date, end: Date) {
        let day = calendar.startOfDay(for: logicalDay)
        let start = rolloverMoment(on: day)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        return (start, rolloverMoment(on: nextDay))
    }

    /// Wall-clock date of a planned time of `logicalDay`. Times earlier than the rollover move to
    /// the next calendar date.
    public func slotDate(on logicalDay: Date, hour: Int, minute: Int) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: logicalDay)
        components.hour = hour
        components.minute = minute
        components.second = 0
        guard let date = calendar.date(from: components) else { return nil }
        return isBeforeRollover(hour * 60 + minute) ? calendar.date(byAdding: .day, value: 1, to: date) : date
    }

    /// Whether a time of day (minutes since midnight) falls before the rollover, i.e. into the
    /// part of the logical day that sits on the next calendar date.
    public func isBeforeRollover(_ minutesSinceMidnight: Int) -> Bool {
        minutesSinceMidnight < rolloverMinutes
    }

    /// The first rollover moment strictly after `date`.
    public func nextRollover(after date: Date) -> Date {
        window(for: logicalDay(containing: date)).end
    }

    private func rolloverMoment(on day: Date) -> Date {
        calendar.date(byAdding: .minute, value: rolloverMinutes, to: day) ?? day
    }

    private static func clamped(_ minutes: Int) -> Int {
        min(max(minutes, 0), 23 * 60 + 59)
    }
}
