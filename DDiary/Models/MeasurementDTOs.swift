import Foundation

public struct BPMeasurementDTO: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let systolic: Int
    public let diastolic: Int
    public let pulse: Int
    public let note: String?

    public init(id: UUID = UUID(), timestamp: Date = .now, systolic: Int, diastolic: Int, pulse: Int, note: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.systolic = systolic
        self.diastolic = diastolic
        self.pulse = pulse
        self.note = note
    }
}

public struct GlucoseMeasurementDTO: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let value: Double
    public let unit: GlucoseUnit
    public let measurementType: GlucoseMeasurementType
    public let mealSlot: MealSlot
    public let note: String?

    public init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        value: Double,
        unit: GlucoseUnit = .mmolL,
        measurementType: GlucoseMeasurementType = .beforeMeal,
        mealSlot: MealSlot = .none,
        note: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.value = value
        self.unit = unit
        self.measurementType = measurementType
        self.mealSlot = mealSlot
        self.note = note
    }
}

public struct GlucoseRotationStateDTO: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let participatingMeals: [MealSlot]
    public let currentMealIndex: Int
    public let completionState: GlucoseRotationCompletionState
    public let beforeTimestamp: Date?
    public let afterTimestamp: Date?

    public init(
        id: UUID = UUID(),
        participatingMeals: [MealSlot] = MealSlot.allCases,
        currentMealIndex: Int = 0,
        completionState: GlucoseRotationCompletionState = .none,
        beforeTimestamp: Date? = nil,
        afterTimestamp: Date? = nil
    ) {
        self.id = id
        self.participatingMeals = participatingMeals
        self.currentMealIndex = currentMealIndex
        self.completionState = completionState
        self.beforeTimestamp = beforeTimestamp
        self.afterTimestamp = afterTimestamp
    }
}

public struct UserSettingsDTO: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let glucoseUnit: GlucoseUnit
    public let bpSystolicMin: Int
    public let bpSystolicMax: Int
    public let bpDiastolicMin: Int
    public let bpDiastolicMax: Int
    public let glucoseMin: Double
    public let glucoseMax: Double
    public let breakfastTime: TimeOfDay
    public let lunchTime: TimeOfDay
    public let dinnerTime: TimeOfDay
    public let bedtimeSlotEnabled: Bool
    public let bpTimes: [TimeOfDay]
    public let bpActiveWeekdays: Set<Int>
    public let enableBeforeMeal: Bool
    public let enableAfterMeal2h: Bool
    public let enableBedtime: Bool
    public let enableDailyCycleMode: Bool
    public let currentCycleIndex: Int

    public init(
        id: UUID = UUID(),
        glucoseUnit: GlucoseUnit = .mmolL,
        bpSystolicMin: Int = 90,
        bpSystolicMax: Int = 140,
        bpDiastolicMin: Int = 60,
        bpDiastolicMax: Int = 90,
        glucoseMin: Double = 4.0,
        glucoseMax: Double = 7.8,
        breakfastTime: TimeOfDay = TimeOfDay(hour: 8, minute: 0),
        lunchTime: TimeOfDay = TimeOfDay(hour: 12, minute: 0),
        dinnerTime: TimeOfDay = TimeOfDay(hour: 18, minute: 0),
        bedtimeSlotEnabled: Bool = true,
        bpTimes: [TimeOfDay] = [TimeOfDay(hour: 8, minute: 0), TimeOfDay(hour: 20, minute: 0)],
        bpActiveWeekdays: Set<Int> = Set(1...7),
        enableBeforeMeal: Bool = true,
        enableAfterMeal2h: Bool = true,
        enableBedtime: Bool = true,
        enableDailyCycleMode: Bool = false,
        currentCycleIndex: Int = 0
    ) {
        self.id = id
        self.glucoseUnit = glucoseUnit
        self.bpSystolicMin = bpSystolicMin
        self.bpSystolicMax = bpSystolicMax
        self.bpDiastolicMin = bpDiastolicMin
        self.bpDiastolicMax = bpDiastolicMax
        self.glucoseMin = glucoseMin
        self.glucoseMax = glucoseMax
        self.breakfastTime = breakfastTime
        self.lunchTime = lunchTime
        self.dinnerTime = dinnerTime
        self.bedtimeSlotEnabled = bedtimeSlotEnabled
        self.bpTimes = bpTimes
        self.bpActiveWeekdays = bpActiveWeekdays
        self.enableBeforeMeal = enableBeforeMeal
        self.enableAfterMeal2h = enableAfterMeal2h
        self.enableBedtime = enableBedtime
        self.enableDailyCycleMode = enableDailyCycleMode
        self.currentCycleIndex = currentCycleIndex
    }
}

// MARK: - Mappers
public extension BPMeasurementDTO {
    init(model: BPMeasurementModel) {
        self.init(
            id: model.id,
            timestamp: model.timestamp,
            systolic: model.systolic,
            diastolic: model.diastolic,
            pulse: model.pulse,
            note: model.note
        )
    }

    func applying(to model: BPMeasurementModel) {
        model.timestamp = timestamp
        model.systolic = systolic
        model.diastolic = diastolic
        model.pulse = pulse
        model.note = note
    }

    func makeModel() -> BPMeasurementModel {
        BPMeasurementModel(
            id: id,
            timestamp: timestamp,
            systolic: systolic,
            diastolic: diastolic,
            pulse: pulse,
            note: note
        )
    }
}

public extension GlucoseMeasurementDTO {
    init(model: GlucoseMeasurementModel) {
        self.init(
            id: model.id,
            timestamp: model.timestamp,
            value: model.value,
            unit: model.unit,
            measurementType: model.measurementType,
            mealSlot: model.mealSlot,
            note: model.note
        )
    }

    func applying(to model: GlucoseMeasurementModel) {
        model.timestamp = timestamp
        model.value = value
        model.unit = unit
        model.measurementType = measurementType
        model.mealSlot = mealSlot
        model.note = note
    }

    func makeModel() -> GlucoseMeasurementModel {
        GlucoseMeasurementModel(
            id: id,
            timestamp: timestamp,
            value: value,
            unit: unit,
            measurementType: measurementType,
            mealSlot: mealSlot,
            note: note
        )
    }
}

public extension GlucoseRotationStateDTO {
    init(model: GlucoseRotationConfigModel) {
        self.init(
            id: model.id,
            participatingMeals: model.participatingMeals,
            currentMealIndex: model.currentMealIndex,
            completionState: model.completionState,
            beforeTimestamp: model.beforeTimestamp,
            afterTimestamp: model.afterTimestamp
        )
    }

    func applying(to model: GlucoseRotationConfigModel) {
        model.participatingMeals = participatingMeals
        model.currentMealIndex = currentMealIndex
        model.completionState = completionState
        model.beforeTimestamp = beforeTimestamp
        model.afterTimestamp = afterTimestamp
    }

    func makeModel() -> GlucoseRotationConfigModel {
        GlucoseRotationConfigModel(
            id: id,
            participatingMeals: participatingMeals,
            currentMealIndex: currentMealIndex,
            completionState: completionState,
            beforeTimestamp: beforeTimestamp,
            afterTimestamp: afterTimestamp
        )
    }
}

public extension UserSettingsDTO {
    init(model: UserSettings) {
        self.init(
            id: model.id,
            glucoseUnit: model.glucoseUnit,
            bpSystolicMin: model.bpSystolicMin,
            bpSystolicMax: model.bpSystolicMax,
            bpDiastolicMin: model.bpDiastolicMin,
            bpDiastolicMax: model.bpDiastolicMax,
            glucoseMin: model.glucoseMin,
            glucoseMax: model.glucoseMax,
            breakfastTime: model.breakfastTime,
            lunchTime: model.lunchTime,
            dinnerTime: model.dinnerTime,
            bedtimeSlotEnabled: model.bedtimeSlotEnabled,
            bpTimes: model.bpTimes,
            bpActiveWeekdays: model.bpActiveWeekdays,
            enableBeforeMeal: model.enableBeforeMeal,
            enableAfterMeal2h: model.enableAfterMeal2h,
            enableBedtime: model.enableBedtime,
            enableDailyCycleMode: model.enableDailyCycleMode,
            currentCycleIndex: model.currentCycleIndex
        )
    }

    func applying(to model: UserSettings) {
        model.glucoseUnit = glucoseUnit
        model.bpSystolicMin = bpSystolicMin
        model.bpSystolicMax = bpSystolicMax
        model.bpDiastolicMin = bpDiastolicMin
        model.bpDiastolicMax = bpDiastolicMax
        model.glucoseMin = glucoseMin
        model.glucoseMax = glucoseMax
        model.breakfastTime = breakfastTime
        model.lunchTime = lunchTime
        model.dinnerTime = dinnerTime
        model.bedtimeSlotEnabled = bedtimeSlotEnabled
        model.bpTimes = bpTimes
        model.bpActiveWeekdays = bpActiveWeekdays
        model.enableBeforeMeal = enableBeforeMeal
        model.enableAfterMeal2h = enableAfterMeal2h
        model.enableBedtime = enableBedtime
        model.enableDailyCycleMode = enableDailyCycleMode
        model.currentCycleIndex = currentCycleIndex
    }

    func makeModel() -> UserSettings {
        UserSettings(
            id: id,
            glucoseUnit: glucoseUnit,
            bpSystolicMin: bpSystolicMin,
            bpSystolicMax: bpSystolicMax,
            bpDiastolicMin: bpDiastolicMin,
            bpDiastolicMax: bpDiastolicMax,
            glucoseMin: glucoseMin,
            glucoseMax: glucoseMax,
            breakfastTime: breakfastTime,
            lunchTime: lunchTime,
            dinnerTime: dinnerTime,
            bedtimeSlotEnabled: bedtimeSlotEnabled,
            bpTimes: bpTimes,
            bpActiveWeekdays: bpActiveWeekdays,
            enableBeforeMeal: enableBeforeMeal,
            enableAfterMeal2h: enableAfterMeal2h,
            enableBedtime: enableBedtime,
            enableDailyCycleMode: enableDailyCycleMode,
            currentCycleIndex: currentCycleIndex
        )
    }
}
