import Foundation

// MARK: - DTOs

public struct BPScheduledSlot: Sendable, Equatable {
    public let date: Date
    public let completed: Bool

    public init(date: Date, completed: Bool) {
        self.date = date
        self.completed = completed
    }
}

public struct GlucosePlannedSlot: Sendable, Equatable {
    public let mealSlot: MealSlot
    public let measurementType: GlucoseMeasurementType
    public let date: Date
    public let completed: Bool

    public init(mealSlot: MealSlot, measurementType: GlucoseMeasurementType, date: Date, completed: Bool) {
        self.mealSlot = mealSlot
        self.measurementType = measurementType
        self.date = date
        self.completed = completed
    }
}

public struct TodayOverview: Sendable, Equatable {
    public let bpSlots: [BPScheduledSlot]
    public let glucoseSlots: [GlucosePlannedSlot]

    public init(bpSlots: [BPScheduledSlot], glucoseSlots: [GlucosePlannedSlot]) {
        self.bpSlots = bpSlots
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

    /// Computes today's planned slots from `UserSettings` and marks slots as completed when
    /// a matching measurement exists within a tolerance window.
    public func compute(today: Date = Date()) async -> TodayOverview {
        let calendar = Calendar.current

        // Fetch settings (MainActor) for schedule definitions
        let settings: UserSettings
        do {
            settings = try await settingsRepository.getOrCreate()
        } catch {
            // Fallback to sensible defaults if settings cannot be loaded
            return Self.defaultOverview(for: today, calendar: calendar)
        }

        let dayRange = Self.dayRange(for: today, calendar: calendar)

        // Build BP scheduled dates from minutes since midnight
        let bpDates: [Date] = settings.bpTimes.compactMap { minutes in
            let hour = minutes / 60
            let minute = minutes % 60
            let comps = DateComponents(hour: hour, minute: minute)
            return Self.date(on: today, using: comps, calendar: calendar)
        }.sorted()

        // Build Glucose planned slots from meal times and toggles
        var glucosePlanned: [(slot: GlucosePlannedSlot, baseDate: Date)] = []
        // Breakfast
        if let breakfast = Self.date(on: today, using: DateComponents(hour: settings.breakfastHour, minute: settings.breakfastMinute), calendar: calendar) {
            if settings.enableBeforeMeal {
                glucosePlanned.append((GlucosePlannedSlot(mealSlot: .breakfast, measurementType: .beforeMeal, date: breakfast, completed: false), breakfast))
            }
            if settings.enableAfterMeal2h, let after = calendar.date(byAdding: .hour, value: 2, to: breakfast) {
                glucosePlanned.append((GlucosePlannedSlot(mealSlot: .breakfast, measurementType: .afterMeal2h, date: after, completed: false), after))
            }
        }
        // Lunch
        if let lunch = Self.date(on: today, using: DateComponents(hour: settings.lunchHour, minute: settings.lunchMinute), calendar: calendar) {
            if settings.enableBeforeMeal {
                glucosePlanned.append((GlucosePlannedSlot(mealSlot: .lunch, measurementType: .beforeMeal, date: lunch, completed: false), lunch))
            }
            if settings.enableAfterMeal2h, let after = calendar.date(byAdding: .hour, value: 2, to: lunch) {
                glucosePlanned.append((GlucosePlannedSlot(mealSlot: .lunch, measurementType: .afterMeal2h, date: after, completed: false), after))
            }
        }
        // Dinner
        if let dinner = Self.date(on: today, using: DateComponents(hour: settings.dinnerHour, minute: settings.dinnerMinute), calendar: calendar) {
            if settings.enableBeforeMeal {
                glucosePlanned.append((GlucosePlannedSlot(mealSlot: .dinner, measurementType: .beforeMeal, date: dinner, completed: false), dinner))
            }
            if settings.enableAfterMeal2h, let after = calendar.date(byAdding: .hour, value: 2, to: dinner) {
                glucosePlanned.append((GlucosePlannedSlot(mealSlot: .dinner, measurementType: .afterMeal2h, date: after, completed: false), after))
            }
        }
        // Bedtime (use 22:00 if enabled)
        if settings.enableBedtime, let bedtime = Self.date(on: today, using: DateComponents(hour: 22, minute: 0), calendar: calendar) {
            glucosePlanned.append((GlucosePlannedSlot(mealSlot: .none, measurementType: .bedtime, date: bedtime, completed: false), bedtime))
        }

        glucosePlanned.sort { $0.baseDate < $1.baseDate }

        // Fetch today's measurements to determine completion
        let bpMeasurements: [BPMeasurement]
        let glucoseMeasurements: [GlucoseMeasurement]
        do {
            bpMeasurements = try await measurementsRepository.bpMeasurements(from: dayRange.start, to: dayRange.end)
            glucoseMeasurements = try await measurementsRepository.glucoseMeasurements(from: dayRange.start, to: dayRange.end)
        } catch {
            // If fetching fails, just consider nothing completed
            let bpSlots = bpDates.map { BPScheduledSlot(date: $0, completed: false) }
            let glSlots = glucosePlanned.map { (pair) in pair.slot }
            return TodayOverview(bpSlots: bpSlots, glucoseSlots: glSlots)
        }

        // Mark BP completion by assigning each measurement to the nearest scheduled slot (no time tolerance)
        var unassignedIndices = Array(bpDates.indices)
        var assigned = Set<Int>()
        let measurementsSorted = bpMeasurements.sorted { $0.timestamp < $1.timestamp }
        for m in measurementsSorted {
            guard let nearest = unassignedIndices.min(by: { lhs, rhs in
                let dl = abs(bpDates[lhs].timeIntervalSince(m.timestamp))
                let dr = abs(bpDates[rhs].timeIntervalSince(m.timestamp))
                if dl == dr {
                    // Prefer the slot at or after the measurement time when equidistant
                    let lFuture = bpDates[lhs] >= m.timestamp
                    let rFuture = bpDates[rhs] >= m.timestamp
                    if lFuture != rFuture { return lFuture }
                    return lhs < rhs
                }
                return dl < dr
            }) else { break }
            assigned.insert(nearest)
            unassignedIndices.removeAll { $0 == nearest }
            if unassignedIndices.isEmpty { break }
        }
        let bpSlots: [BPScheduledSlot] = bpDates.enumerated().map { (index, date) in
            BPScheduledSlot(date: date, completed: assigned.contains(index))
        }

        // Mark Glucose completion by slot kind (ignore time-of-day)
        let glSlots: [GlucosePlannedSlot] = glucosePlanned.map { (slot, baseDate) in
            let completed = glucoseMeasurements.contains { m in
                m.measurementType == slot.measurementType && m.mealSlot == slot.mealSlot
            }
            return GlucosePlannedSlot(mealSlot: slot.mealSlot, measurementType: slot.measurementType, date: baseDate, completed: completed)
        }

        return TodayOverview(bpSlots: bpSlots, glucoseSlots: glSlots)
    }

    // MARK: - Helpers

    private static func date(on base: Date, using components: DateComponents, calendar: Calendar) -> Date? {
        var day = calendar.dateComponents([.year, .month, .day], from: base)
        day.hour = components.hour
        day.minute = components.minute
        day.second = components.second ?? 0
        return calendar.date(from: day)
    }

    private static func dayRange(for date: Date, calendar: Calendar) -> (start: Date, end: Date) {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? start
        return (start, end)
    }

    // Fallback overview using hardcoded defaults when settings cannot be loaded
    private static func defaultOverview(for today: Date, calendar: Calendar) -> TodayOverview {
        let defaultBPTimes: [DateComponents] = [
            DateComponents(hour: 9, minute: 0),
            DateComponents(hour: 21, minute: 0)
        ]
        let bpDates: [Date] = defaultBPTimes.compactMap { comps in
            date(on: today, using: comps, calendar: calendar)
        }.sorted()

        var glucose: [GlucosePlannedSlot] = []
        if let breakfast = date(on: today, using: DateComponents(hour: 8, minute: 0), calendar: calendar) {
            glucose.append(GlucosePlannedSlot(mealSlot: .breakfast, measurementType: .beforeMeal, date: breakfast, completed: false))
            if let after = calendar.date(byAdding: .hour, value: 2, to: breakfast) {
                glucose.append(GlucosePlannedSlot(mealSlot: .breakfast, measurementType: .afterMeal2h, date: after, completed: false))
            }
        }
        if let lunch = date(on: today, using: DateComponents(hour: 13, minute: 0), calendar: calendar) {
            glucose.append(GlucosePlannedSlot(mealSlot: .lunch, measurementType: .beforeMeal, date: lunch, completed: false))
            if let after = calendar.date(byAdding: .hour, value: 2, to: lunch) {
                glucose.append(GlucosePlannedSlot(mealSlot: .lunch, measurementType: .afterMeal2h, date: after, completed: false))
            }
        }
        if let dinner = date(on: today, using: DateComponents(hour: 19, minute: 0), calendar: calendar) {
            glucose.append(GlucosePlannedSlot(mealSlot: .dinner, measurementType: .beforeMeal, date: dinner, completed: false))
            if let after = calendar.date(byAdding: .hour, value: 2, to: dinner) {
                glucose.append(GlucosePlannedSlot(mealSlot: .dinner, measurementType: .afterMeal2h, date: after, completed: false))
            }
        }
        if let bedtime = date(on: today, using: DateComponents(hour: 22, minute: 0), calendar: calendar) {
            glucose.append(GlucosePlannedSlot(mealSlot: .none, measurementType: .bedtime, date: bedtime, completed: false))
        }

        let bpSlots = bpDates.map { BPScheduledSlot(date: $0, completed: false) }
        return TodayOverview(bpSlots: bpSlots, glucoseSlots: glucose.sorted { $0.date < $1.date })
    }
}
