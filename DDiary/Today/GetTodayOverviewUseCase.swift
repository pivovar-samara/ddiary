import Foundation

// MARK: - DTOs

public struct GlucosePlannedSlot: Sendable, Equatable {
    public let mealSlot: MealSlot
    public let measurementType: GlucoseMeasurementType
    public let date: Date

    public init(mealSlot: MealSlot, measurementType: GlucoseMeasurementType, date: Date) {
        self.mealSlot = mealSlot
        self.measurementType = measurementType
        self.date = date
    }
}

public struct TodayOverview: Sendable, Equatable {
    public let bpTimes: [Date]
    public let glucoseSlots: [GlucosePlannedSlot]

    public init(bpTimes: [Date], glucoseSlots: [GlucosePlannedSlot]) {
        self.bpTimes = bpTimes
        self.glucoseSlots = glucoseSlots
    }
}

// MARK: - Use Case

@MainActor
public final class GetTodayOverviewUseCase {
    private let measurementsRepository: any MeasurementsRepository
    private let settingsRepository: any SettingsRepository

    public init(
        measurementsRepository: any MeasurementsRepository,
        settingsRepository: any SettingsRepository
    ) {
        self.measurementsRepository = measurementsRepository
        self.settingsRepository = settingsRepository
    }

    /// Minimal computation of today's planned slots using default times.
    /// In a later phase, replace defaults with values from `UserSettings` fetched via `settingsRepository`,
    /// and mark completed slots by looking up today's measurements via `measurementsRepository`.
    public func compute(today: Date = Date()) async -> TodayOverview {
        let calendar = Calendar.current

        // Default schedule (can be replaced by `UserSettings` later)
        let defaultBPTimes: [DateComponents] = [
            DateComponents(hour: 9, minute: 0),
            DateComponents(hour: 21, minute: 0)
        ]

        let defaultBreakfast = DateComponents(hour: 8, minute: 0)
        let defaultLunch = DateComponents(hour: 13, minute: 0)
        let defaultDinner = DateComponents(hour: 19, minute: 0)
        let defaultBedtime = DateComponents(hour: 22, minute: 0)

        let bpDates: [Date] = defaultBPTimes.compactMap { comps in
            date(on: today, using: comps, calendar: calendar)
        }.sorted()

        var glucose: [GlucosePlannedSlot] = []

        if let breakfast = date(on: today, using: defaultBreakfast, calendar: calendar) {
            glucose.append(GlucosePlannedSlot(mealSlot: .breakfast, measurementType: .beforeMeal, date: breakfast))
            if let after = calendar.date(byAdding: .hour, value: 2, to: breakfast) {
                glucose.append(GlucosePlannedSlot(mealSlot: .breakfast, measurementType: .afterMeal2h, date: after))
            }
        }
        if let lunch = date(on: today, using: defaultLunch, calendar: calendar) {
            glucose.append(GlucosePlannedSlot(mealSlot: .lunch, measurementType: .beforeMeal, date: lunch))
            if let after = calendar.date(byAdding: .hour, value: 2, to: lunch) {
                glucose.append(GlucosePlannedSlot(mealSlot: .lunch, measurementType: .afterMeal2h, date: after))
            }
        }
        if let dinner = date(on: today, using: defaultDinner, calendar: calendar) {
            glucose.append(GlucosePlannedSlot(mealSlot: .dinner, measurementType: .beforeMeal, date: dinner))
            if let after = calendar.date(byAdding: .hour, value: 2, to: dinner) {
                glucose.append(GlucosePlannedSlot(mealSlot: .dinner, measurementType: .afterMeal2h, date: after))
            }
        }
        if let bedtime = date(on: today, using: defaultBedtime, calendar: calendar) {
            glucose.append(GlucosePlannedSlot(mealSlot: .none, measurementType: .bedtime, date: bedtime))
        }

        glucose.sort { $0.date < $1.date }

        return TodayOverview(bpTimes: bpDates, glucoseSlots: glucose)
    }

    // MARK: - Helpers

    private func date(on base: Date, using components: DateComponents, calendar: Calendar) -> Date? {
        var day = calendar.dateComponents([.year, .month, .day], from: base)
        day.hour = components.hour
        day.minute = components.minute
        day.second = components.second ?? 0
        return calendar.date(from: day)
    }
}
