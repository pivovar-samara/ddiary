import Foundation

// MARK: - DTOs

public struct BPScheduledSlot: Sendable, Equatable {
    public let date: Date
    public let completed: Bool
    public let matchedMeasurementId: UUID?

    public init(date: Date, completed: Bool, matchedMeasurementId: UUID?) {
        self.date = date
        self.completed = completed
        self.matchedMeasurementId = matchedMeasurementId
    }
}

public struct GlucosePlannedSlot: Sendable, Equatable {
    public let mealSlot: MealSlot
    public let measurementType: GlucoseMeasurementType
    public let date: Date
    public let completed: Bool
    public let matchedMeasurementId: UUID?

    public init(mealSlot: MealSlot, measurementType: GlucoseMeasurementType, date: Date, completed: Bool, matchedMeasurementId: UUID?) {
        self.mealSlot = mealSlot
        self.measurementType = measurementType
        self.date = date
        self.completed = completed
        self.matchedMeasurementId = matchedMeasurementId
    }
}

public struct TodayOverview: Sendable, Equatable {
    public let bpSlots: [BPScheduledSlot]
    public let glucoseSlots: [GlucosePlannedSlot]
    public let isDailyCycleModeEnabled: Bool

    public init(
        bpSlots: [BPScheduledSlot],
        glucoseSlots: [GlucosePlannedSlot],
        isDailyCycleModeEnabled: Bool = false
    ) {
        self.bpSlots = bpSlots
        self.glucoseSlots = glucoseSlots
        self.isDailyCycleModeEnabled = isDailyCycleModeEnabled
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

        let cycleAnchorDate: Date? = await persistCycleAnchorIfNeeded(settings: settings, today: today, calendar: calendar)

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
        if settings.enableDailyCycleMode {
            let cycleConfig = GlucoseCycleConfiguration(
                anchorDate: cycleAnchorDate ?? calendar.startOfDay(for: today),
                breakfast: DateComponents(hour: settings.breakfastHour, minute: settings.breakfastMinute),
                lunch: DateComponents(hour: settings.lunchHour, minute: settings.lunchMinute),
                dinner: DateComponents(hour: settings.dinnerHour, minute: settings.dinnerMinute),
                bedtime: DateComponents(hour: settings.bedtimeHour, minute: settings.bedtimeMinute)
            )
            let reminders = GlucoseCyclePlanner.reminders(on: today, configuration: cycleConfig, calendar: calendar)
            glucosePlanned = reminders.map { reminder in
                let slot = GlucosePlannedSlot(
                    mealSlot: reminder.mealSlot,
                    measurementType: reminder.measurementType,
                    date: reminder.date,
                    completed: false,
                    matchedMeasurementId: nil
                )
                return (slot, reminder.date)
            }
        } else {
            // Breakfast
            if let breakfast = Self.date(on: today, using: DateComponents(hour: settings.breakfastHour, minute: settings.breakfastMinute), calendar: calendar) {
                if settings.enableBeforeMeal {
                    glucosePlanned.append((GlucosePlannedSlot(mealSlot: .breakfast, measurementType: .beforeMeal, date: breakfast, completed: false, matchedMeasurementId: nil), breakfast))
                }
                if settings.enableAfterMeal2h, let after = calendar.date(byAdding: .hour, value: 2, to: breakfast) {
                    glucosePlanned.append((GlucosePlannedSlot(mealSlot: .breakfast, measurementType: .afterMeal2h, date: after, completed: false, matchedMeasurementId: nil), after))
                }
            }
            // Lunch
            if let lunch = Self.date(on: today, using: DateComponents(hour: settings.lunchHour, minute: settings.lunchMinute), calendar: calendar) {
                if settings.enableBeforeMeal {
                    glucosePlanned.append((GlucosePlannedSlot(mealSlot: .lunch, measurementType: .beforeMeal, date: lunch, completed: false, matchedMeasurementId: nil), lunch))
                }
                if settings.enableAfterMeal2h, let after = calendar.date(byAdding: .hour, value: 2, to: lunch) {
                    glucosePlanned.append((GlucosePlannedSlot(mealSlot: .lunch, measurementType: .afterMeal2h, date: after, completed: false, matchedMeasurementId: nil), after))
                }
            }
            // Dinner
            if let dinner = Self.date(on: today, using: DateComponents(hour: settings.dinnerHour, minute: settings.dinnerMinute), calendar: calendar) {
                if settings.enableBeforeMeal {
                    glucosePlanned.append((GlucosePlannedSlot(mealSlot: .dinner, measurementType: .beforeMeal, date: dinner, completed: false, matchedMeasurementId: nil), dinner))
                }
                if settings.enableAfterMeal2h, let after = calendar.date(byAdding: .hour, value: 2, to: dinner) {
                    glucosePlanned.append((GlucosePlannedSlot(mealSlot: .dinner, measurementType: .afterMeal2h, date: after, completed: false, matchedMeasurementId: nil), after))
                }
            }
            // Bedtime (use user-configured time when slot enabled)
            if settings.bedtimeSlotEnabled,
               let bedtime = Self.date(on: today, using: DateComponents(hour: settings.bedtimeHour, minute: settings.bedtimeMinute), calendar: calendar) {
                glucosePlanned.append((GlucosePlannedSlot(mealSlot: .none, measurementType: .bedtime, date: bedtime, completed: false, matchedMeasurementId: nil), bedtime))
            }
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
            let bpSlots = bpDates.map { BPScheduledSlot(date: $0, completed: false, matchedMeasurementId: nil) }
            let glSlots = glucosePlanned.map { (pair) in
                GlucosePlannedSlot(mealSlot: pair.slot.mealSlot,
                                  measurementType: pair.slot.measurementType,
                                  date: pair.baseDate,
                                  completed: false,
                                  matchedMeasurementId: nil)
            }
            return TodayOverview(
                bpSlots: bpSlots,
                glucoseSlots: glSlots,
                isDailyCycleModeEnabled: settings.enableDailyCycleMode
            )
        }

        // Mark BP completion by assigning each measurement to the nearest scheduled slot (no time tolerance)
        var unassignedIndices = Array(bpDates.indices)
        var assignment: [Int: UUID] = [:]
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
            assignment[nearest] = m.id
            unassignedIndices.removeAll { $0 == nearest }
            if unassignedIndices.isEmpty { break }
        }
        let bpSlots: [BPScheduledSlot] = bpDates.enumerated().map { (index, date) in
            let id = assignment[index]
            return BPScheduledSlot(date: date, completed: id != nil, matchedMeasurementId: id)
        }

        // Mark Glucose completion by slot kind, picking the nearest measurement per slot
        var unmatchedGlucose = glucoseMeasurements.sorted { $0.timestamp < $1.timestamp }
        let glSlots: [GlucosePlannedSlot] = glucosePlanned.map { (slot, baseDate) in
            let candidates = unmatchedGlucose.enumerated().filter { _, m in
                m.measurementType == slot.measurementType && m.mealSlot == slot.mealSlot
            }
            if let nearest = candidates.min(by: { lhs, rhs in
                abs(lhs.element.timestamp.timeIntervalSince(baseDate)) < abs(rhs.element.timestamp.timeIntervalSince(baseDate))
            }) {
                let matched = unmatchedGlucose.remove(at: nearest.offset)
                return GlucosePlannedSlot(mealSlot: slot.mealSlot, measurementType: slot.measurementType, date: baseDate, completed: true, matchedMeasurementId: matched.id)
            } else {
                return GlucosePlannedSlot(mealSlot: slot.mealSlot, measurementType: slot.measurementType, date: baseDate, completed: false, matchedMeasurementId: nil)
            }
        }

        return TodayOverview(
            bpSlots: bpSlots,
            glucoseSlots: glSlots,
            isDailyCycleModeEnabled: settings.enableDailyCycleMode
        )
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

    private func persistCycleAnchorIfNeeded(settings: UserSettings, today: Date, calendar: Calendar) async -> Date? {
        guard settings.enableDailyCycleMode else { return nil }
        let anchorDate = settings.dailyCycleAnchorDate
            ?? GlucoseCyclePlanner.fallbackAnchorDate(
                currentCycleIndex: settings.currentCycleIndex,
                referenceDate: today,
                calendar: calendar
            )
        guard settings.dailyCycleAnchorDate == nil else { return anchorDate }
        settings.dailyCycleAnchorDate = anchorDate
        do {
            try await settingsRepository.save(settings)
        } catch {
            // Best-effort persistence only; `anchorDate` still drives this compute cycle.
        }
        return anchorDate
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
            glucose.append(GlucosePlannedSlot(mealSlot: .breakfast, measurementType: .beforeMeal, date: breakfast, completed: false, matchedMeasurementId: nil))
            if let after = calendar.date(byAdding: .hour, value: 2, to: breakfast) {
                glucose.append(GlucosePlannedSlot(mealSlot: .breakfast, measurementType: .afterMeal2h, date: after, completed: false, matchedMeasurementId: nil))
            }
        }
        if let lunch = date(on: today, using: DateComponents(hour: 13, minute: 0), calendar: calendar) {
            glucose.append(GlucosePlannedSlot(mealSlot: .lunch, measurementType: .beforeMeal, date: lunch, completed: false, matchedMeasurementId: nil))
            if let after = calendar.date(byAdding: .hour, value: 2, to: lunch) {
                glucose.append(GlucosePlannedSlot(mealSlot: .lunch, measurementType: .afterMeal2h, date: after, completed: false, matchedMeasurementId: nil))
            }
        }
        if let dinner = date(on: today, using: DateComponents(hour: 19, minute: 0), calendar: calendar) {
            glucose.append(GlucosePlannedSlot(mealSlot: .dinner, measurementType: .beforeMeal, date: dinner, completed: false, matchedMeasurementId: nil))
            if let after = calendar.date(byAdding: .hour, value: 2, to: dinner) {
                glucose.append(GlucosePlannedSlot(mealSlot: .dinner, measurementType: .afterMeal2h, date: after, completed: false, matchedMeasurementId: nil))
            }
        }
        let bpSlots = bpDates.map { BPScheduledSlot(date: $0, completed: false, matchedMeasurementId: nil) }
        return TodayOverview(
            bpSlots: bpSlots,
            glucoseSlots: glucose.sorted { $0.date < $1.date },
            isDailyCycleModeEnabled: false
        )
    }
}
