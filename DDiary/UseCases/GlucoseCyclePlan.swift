import Foundation

public enum GlucoseCycleStep: Int, CaseIterable, Sendable {
    case breakfastDay = 0
    case lunchDay = 1
    case dinnerDay = 2
    case bedtimeDay = 3
}

public struct GlucoseCycleConfiguration: Sendable, Equatable {
    public let anchorDate: Date
    public let breakfast: DateComponents
    public let lunch: DateComponents
    public let dinner: DateComponents
    public let bedtime: DateComponents
    /// Per-day step overrides keyed by "yyyy-MM-dd" from `GlucoseCyclePlanner.dateKey(for:calendar:)`.
    public let overrides: [String: Int]

    public init(
        anchorDate: Date,
        breakfast: DateComponents,
        lunch: DateComponents,
        dinner: DateComponents,
        bedtime: DateComponents,
        overrides: [String: Int] = [:]
    ) {
        self.anchorDate = anchorDate
        self.breakfast = breakfast
        self.lunch = lunch
        self.dinner = dinner
        self.bedtime = bedtime
        self.overrides = overrides
    }
}

public struct GlucoseCycleReminder: Sendable, Equatable {
    public let mealSlot: MealSlot
    public let measurementType: GlucoseMeasurementType
    public let date: Date

    public init(mealSlot: MealSlot, measurementType: GlucoseMeasurementType, date: Date) {
        self.mealSlot = mealSlot
        self.measurementType = measurementType
        self.date = date
    }
}

enum GlucoseCyclePlanner {

    // MARK: - Date key helpers

    /// Returns the canonical "yyyy-MM-dd" key for a date. Used as the key in `cycleOverrides`.
    static func dateKey(for date: Date, calendar: Calendar = .current) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = comps.year, let month = comps.month, let day = comps.day else {
            // Should never happen for a valid Date; assertionFailure catches it during development.
            assertionFailure("GlucoseCyclePlanner.dateKey: missing components for \(date)")
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: date)
        }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Returns a copy of `overrides` with all entries whose key date is on or after `today` removed.
    /// Each key is parsed back to a `Date` for calendar-aware comparison so correctness does not
    /// depend on the string representation being lexicographically ordered.
    ///
    /// Entries whose key cannot be parsed are **kept** (treated as past/unknown) so malformed
    /// keys produced by older clients or future migrations are never silently discarded.
    /// An `assertionFailure` fires in debug builds to surface unexpected keys early.
    static func dropFutureAndTodayOverrides(
        _ overrides: [String: Int],
        today: Date,
        calendar: Calendar = .current
    ) -> [String: Int] {
        let startOfToday = calendar.startOfDay(for: today)
        return overrides.filter { key, _ in
            guard let keyDate = date(fromKey: key, calendar: calendar) else {
                // Keep entries with unparseable keys — we don't know their date, so we
                // cannot classify them as future. Fire in debug to surface bad data early.
                assertionFailure("GlucoseCyclePlanner.dropFutureAndTodayOverrides: unable to parse override key '\(key)'")
                return true
            }
            return calendar.startOfDay(for: keyDate) < startOfToday
        }
    }

    /// Removes override entries older than `keepingDays` days before `today`.
    static func pruneOverrides(
        _ overrides: [String: Int],
        today: Date,
        keepingDays days: Int = 30,
        calendar: Calendar = .current
    ) -> [String: Int] {
        guard let cutoff = calendar.date(
            byAdding: .day, value: -days, to: calendar.startOfDay(for: today)
        ) else { return overrides }
        return overrides.filter { key, _ in
            guard let date = date(fromKey: key, calendar: calendar) else { return false }
            return date >= cutoff
        }
    }

    // MARK: - Fallback anchor (legacy migration)

    static func fallbackAnchorDate(
        currentCycleIndex: Int,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Date {
        let dayStart = calendar.startOfDay(for: referenceDate)
        let normalized = positiveModulo(currentCycleIndex, GlucoseCycleStep.allCases.count)
        return calendar.date(byAdding: .day, value: -normalized, to: dayStart) ?? dayStart
    }

    // MARK: - Step computation

    /// Returns the cycle step for `day`, consulting `overrides` before falling back to the
    /// anchor-based computation. This is the primary entry point for all step lookups.
    static func step(
        on day: Date,
        anchorDate: Date,
        overrides: [String: Int] = [:],
        calendar: Calendar = .current
    ) -> GlucoseCycleStep {
        let key = dateKey(for: day, calendar: calendar)
        if let overrideIndex = overrides[key] {
            let index = positiveModulo(overrideIndex, GlucoseCycleStep.allCases.count)
            return GlucoseCycleStep(rawValue: index) ?? .breakfastDay
        }
        let start = calendar.startOfDay(for: day)
        let anchor = calendar.startOfDay(for: anchorDate)
        let dayDelta = calendar.dateComponents([.day], from: anchor, to: start).day ?? 0
        let index = positiveModulo(dayDelta, GlucoseCycleStep.allCases.count)
        return GlucoseCycleStep(rawValue: index) ?? .breakfastDay
    }

    // MARK: - Reminder generation

    static func reminders(
        on day: Date,
        configuration: GlucoseCycleConfiguration,
        calendar: Calendar = .current
    ) -> [GlucoseCycleReminder] {
        let step = step(
            on: day,
            anchorDate: configuration.anchorDate,
            overrides: configuration.overrides,
            calendar: calendar
        )
        switch step {
        case .breakfastDay:
            return beforeAndAfterReminders(
                on: day,
                mealSlot: .breakfast,
                mealTime: configuration.breakfast,
                calendar: calendar
            )
        case .lunchDay:
            return beforeAndAfterReminders(
                on: day,
                mealSlot: .lunch,
                mealTime: configuration.lunch,
                calendar: calendar
            )
        case .dinnerDay:
            return beforeAndAfterReminders(
                on: day,
                mealSlot: .dinner,
                mealTime: configuration.dinner,
                calendar: calendar
            )
        case .bedtimeDay:
            guard let bedtimeDate = date(on: day, at: configuration.bedtime, calendar: calendar) else { return [] }
            return [GlucoseCycleReminder(mealSlot: .none, measurementType: .bedtime, date: bedtimeDate)]
        }
    }

    // MARK: - Private helpers

    private static func beforeAndAfterReminders(
        on day: Date,
        mealSlot: MealSlot,
        mealTime: DateComponents,
        calendar: Calendar
    ) -> [GlucoseCycleReminder] {
        guard let before = date(on: day, at: mealTime, calendar: calendar) else { return [] }
        guard let after = calendar.date(byAdding: .hour, value: 2, to: before) else {
            return [GlucoseCycleReminder(mealSlot: mealSlot, measurementType: .beforeMeal, date: before)]
        }
        return [
            GlucoseCycleReminder(mealSlot: mealSlot, measurementType: .beforeMeal, date: before),
            GlucoseCycleReminder(mealSlot: mealSlot, measurementType: .afterMeal2h, date: after),
        ]
    }

    private static func date(on day: Date, at components: DateComponents, calendar: Calendar) -> Date? {
        var dayComponents = calendar.dateComponents([.year, .month, .day], from: day)
        dayComponents.hour = components.hour
        dayComponents.minute = components.minute
        dayComponents.second = components.second ?? 0
        return calendar.date(from: dayComponents)
    }

    private static func date(fromKey key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              year > 0, (1...12).contains(month), (1...31).contains(day)
        else { return nil }
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        return calendar.date(from: comps)
    }

    private static func positiveModulo(_ value: Int, _ modulus: Int) -> Int {
        let remainder = value % modulus
        return remainder >= 0 ? remainder : remainder + modulus
    }
}
