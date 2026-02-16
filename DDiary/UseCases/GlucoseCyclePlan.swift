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

    public init(
        anchorDate: Date,
        breakfast: DateComponents,
        lunch: DateComponents,
        dinner: DateComponents,
        bedtime: DateComponents
    ) {
        self.anchorDate = anchorDate
        self.breakfast = breakfast
        self.lunch = lunch
        self.dinner = dinner
        self.bedtime = bedtime
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
    static func fallbackAnchorDate(
        currentCycleIndex: Int,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Date {
        let dayStart = calendar.startOfDay(for: referenceDate)
        let normalized = positiveModulo(currentCycleIndex, GlucoseCycleStep.allCases.count)
        return calendar.date(byAdding: .day, value: -normalized, to: dayStart) ?? dayStart
    }

    static func step(
        on day: Date,
        anchorDate: Date,
        calendar: Calendar = .current
    ) -> GlucoseCycleStep {
        let start = calendar.startOfDay(for: day)
        let anchor = calendar.startOfDay(for: anchorDate)
        let dayDelta = calendar.dateComponents([.day], from: anchor, to: start).day ?? 0
        let index = positiveModulo(dayDelta, GlucoseCycleStep.allCases.count)
        return GlucoseCycleStep(rawValue: index) ?? .breakfastDay
    }

    static func reminders(
        on day: Date,
        configuration: GlucoseCycleConfiguration,
        calendar: Calendar = .current
    ) -> [GlucoseCycleReminder] {
        let step = step(on: day, anchorDate: configuration.anchorDate, calendar: calendar)
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

    private static func positiveModulo(_ value: Int, _ modulus: Int) -> Int {
        let remainder = value % modulus
        return remainder >= 0 ? remainder : remainder + modulus
    }
}
