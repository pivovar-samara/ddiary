//
//  HealthModels.swift
//  DDiary
//
//  Created by Ilia Khokhlov on 26.11.25.
//

import Foundation
import SwiftData

// MARK: - BPMeasurement
@Model
public final class BPMeasurement: Codable, Identifiable {
    public var id: UUID = UUID()
    public var timestamp: Date = Date.now
    public var systolic: Int = 0
    public var diastolic: Int = 0
    public var pulse: Int = 0
    public var comment: String?
    public var googleSyncStatusRaw: String = GoogleSyncStatus.notSynced.rawValue
    public var googleLastError: String?
    public var googleLastSyncAt: Date?

    // Derived strongly-typed status bridged through a raw field for SwiftData persistence
    public var googleSyncStatus: GoogleSyncStatus {
        get { GoogleSyncStatus(rawValue: googleSyncStatusRaw) ?? .notSynced }
        set { googleSyncStatusRaw = newValue.rawValue }
    }

    public init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        systolic: Int,
        diastolic: Int,
        pulse: Int,
        comment: String? = nil,
        googleSyncStatus: GoogleSyncStatus = .notSynced,
        googleLastError: String? = nil,
        googleLastSyncAt: Date? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.systolic = systolic
        self.diastolic = diastolic
        self.pulse = pulse
        self.comment = comment
        self.googleSyncStatusRaw = googleSyncStatus.rawValue
        self.googleLastError = googleLastError
        self.googleLastSyncAt = googleLastSyncAt
    }

    // MARK: Codable
    private enum CodingKeys: String, CodingKey {
        case id, timestamp, systolic, diastolic, pulse, comment
        case googleSyncStatus, googleLastError, googleLastSyncAt
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.timestamp = try container.decode(Date.self, forKey: .timestamp)
        self.systolic = try container.decode(Int.self, forKey: .systolic)
        self.diastolic = try container.decode(Int.self, forKey: .diastolic)
        self.pulse = try container.decode(Int.self, forKey: .pulse)
        self.comment = try container.decodeIfPresent(String.self, forKey: .comment)
        let status = try container.decode(GoogleSyncStatus.self, forKey: .googleSyncStatus)
        self.googleSyncStatusRaw = status.rawValue
        self.googleLastError = try container.decodeIfPresent(String.self, forKey: .googleLastError)
        self.googleLastSyncAt = try container.decodeIfPresent(Date.self, forKey: .googleLastSyncAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(systolic, forKey: .systolic)
        try container.encode(diastolic, forKey: .diastolic)
        try container.encode(pulse, forKey: .pulse)
        try container.encodeIfPresent(comment, forKey: .comment)
        try container.encode(googleSyncStatus, forKey: .googleSyncStatus)
        try container.encodeIfPresent(googleLastError, forKey: .googleLastError)
        try container.encodeIfPresent(googleLastSyncAt, forKey: .googleLastSyncAt)
    }
}

// MARK: - GlucoseMeasurement
@Model
public final class GlucoseMeasurement: Codable, Identifiable {
    public var id: UUID = UUID()
    public var timestamp: Date = Date.now
    public var value: Double = 0.0
    public var unitRaw: String = GlucoseUnit.mmolL.rawValue
    public var measurementTypeRaw: String = GlucoseMeasurementType.beforeMeal.rawValue
    public var mealSlotRaw: String = MealSlot.none.rawValue
    public var comment: String?
    public var googleSyncStatusRaw: String = GoogleSyncStatus.notSynced.rawValue
    public var googleLastError: String?
    public var googleLastSyncAt: Date?

    public var unit: GlucoseUnit {
        get { GlucoseUnit(rawValue: unitRaw) ?? .mmolL }
        set { unitRaw = newValue.rawValue }
    }

    public var measurementType: GlucoseMeasurementType {
        get { GlucoseMeasurementType(rawValue: measurementTypeRaw) ?? .beforeMeal }
        set { measurementTypeRaw = newValue.rawValue }
    }

    public var mealSlot: MealSlot {
        get { MealSlot(rawValue: mealSlotRaw) ?? .none }
        set { mealSlotRaw = newValue.rawValue }
    }

    public var googleSyncStatus: GoogleSyncStatus {
        get { GoogleSyncStatus(rawValue: googleSyncStatusRaw) ?? .notSynced }
        set { googleSyncStatusRaw = newValue.rawValue }
    }

    public init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        value: Double,
        unit: GlucoseUnit = .mmolL,
        measurementType: GlucoseMeasurementType = .beforeMeal,
        mealSlot: MealSlot = .none,
        comment: String? = nil,
        googleSyncStatus: GoogleSyncStatus = .notSynced,
        googleLastError: String? = nil,
        googleLastSyncAt: Date? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.value = value
        self.unitRaw = unit.rawValue
        self.measurementTypeRaw = measurementType.rawValue
        self.mealSlotRaw = mealSlot.rawValue
        self.comment = comment
        self.googleSyncStatusRaw = googleSyncStatus.rawValue
        self.googleLastError = googleLastError
        self.googleLastSyncAt = googleLastSyncAt
    }

    // MARK: Codable
    private enum CodingKeys: String, CodingKey {
        case id, timestamp, value, unit, measurementType, mealSlot, comment
        case googleSyncStatus, googleLastError, googleLastSyncAt
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.timestamp = try container.decode(Date.self, forKey: .timestamp)
        self.value = try container.decode(Double.self, forKey: .value)
        let unit = try container.decode(GlucoseUnit.self, forKey: .unit)
        self.unitRaw = unit.rawValue
        let type = try container.decode(GlucoseMeasurementType.self, forKey: .measurementType)
        self.measurementTypeRaw = type.rawValue
        let slot = try container.decode(MealSlot.self, forKey: .mealSlot)
        self.mealSlotRaw = slot.rawValue
        self.comment = try container.decodeIfPresent(String.self, forKey: .comment)
        let status = try container.decode(GoogleSyncStatus.self, forKey: .googleSyncStatus)
        self.googleSyncStatusRaw = status.rawValue
        self.googleLastError = try container.decodeIfPresent(String.self, forKey: .googleLastError)
        self.googleLastSyncAt = try container.decodeIfPresent(Date.self, forKey: .googleLastSyncAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(value, forKey: .value)
        try container.encode(unit, forKey: .unit)
        try container.encode(measurementType, forKey: .measurementType)
        try container.encode(mealSlot, forKey: .mealSlot)
        try container.encodeIfPresent(comment, forKey: .comment)
        try container.encode(googleSyncStatus, forKey: .googleSyncStatus)
        try container.encodeIfPresent(googleLastError, forKey: .googleLastError)
        try container.encodeIfPresent(googleLastSyncAt, forKey: .googleLastSyncAt)
    }
}

public struct TimeOfDay: Codable, Hashable, Sendable {
    public var hour: Int
    public var minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    public init(_ components: DateComponents) {
        self.hour = components.hour ?? 0
        self.minute = components.minute ?? 0
    }

    public var dateComponents: DateComponents { DateComponents(hour: hour, minute: minute) }
}

// MARK: - UserSettings
@Model
public final class UserSettings: Codable, Identifiable {
    public var id: UUID = UUID()
    public var glucoseUnitRaw: String = GlucoseUnit.mmolL.rawValue

    public var bpSystolicMin: Int = 90
    public var bpSystolicMax: Int = 140
    public var bpDiastolicMin: Int = 60
    public var bpDiastolicMax: Int = 90

    public var glucoseMin: Double = 4.0
    public var glucoseMax: Double = 7.8
    
    public var breakfastTime: TimeOfDay = TimeOfDay(hour: 8, minute: 0)
    public var lunchTime: TimeOfDay = TimeOfDay(hour: 12, minute: 0)
    public var dinnerTime: TimeOfDay = TimeOfDay(hour: 18, minute: 0)

    public var bedtimeSlotEnabled: Bool = true

    public var bpTimes: [TimeOfDay] = [TimeOfDay(hour: 8, minute: 0), TimeOfDay(hour: 20, minute: 0)]

    public var bpActiveWeekdaysMask: Int = 127

    public var bpActiveWeekdays: Set<Int> {
        get {
            var set: Set<Int> = []
            for day in 1...7 {
                if (bpActiveWeekdaysMask & (1 << (day - 1))) != 0 {
                    set.insert(day)
                }
            }
            return set
        }
        set {
            var mask = 0
            for day in newValue {
                guard (1...7).contains(day) else { continue }
                mask |= (1 << (day - 1))
            }
            bpActiveWeekdaysMask = mask
        }
    }

    public var enableBeforeMeal: Bool = true
    public var enableAfterMeal2h: Bool = true
    public var enableBedtime: Bool = true

    public var enableDailyCycleMode: Bool = false
    public var currentCycleIndex: Int = 0

    public var glucoseUnit: GlucoseUnit {
        get { GlucoseUnit(rawValue: glucoseUnitRaw) ?? .mmolL }
        set { glucoseUnitRaw = newValue.rawValue }
    }

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
        self.glucoseUnitRaw = glucoseUnit.rawValue
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

    // Convenience factory for sensible defaults
    public static func `default`() -> UserSettings {
        UserSettings()
    }

    // Codable
    private enum CodingKeys: String, CodingKey {
        case id, glucoseUnit, bpSystolicMin, bpSystolicMax, bpDiastolicMin, bpDiastolicMax
        case glucoseMin, glucoseMax, breakfastTime, lunchTime, dinnerTime
        case bedtimeSlotEnabled, bpTimes, bpActiveWeekdaysMask
        case enableBeforeMeal, enableAfterMeal2h, enableBedtime
        case enableDailyCycleMode, currentCycleIndex
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        let unit = try container.decode(GlucoseUnit.self, forKey: .glucoseUnit)
        self.glucoseUnitRaw = unit.rawValue
        self.bpSystolicMin = try container.decode(Int.self, forKey: .bpSystolicMin)
        self.bpSystolicMax = try container.decode(Int.self, forKey: .bpSystolicMax)
        self.bpDiastolicMin = try container.decode(Int.self, forKey: .bpDiastolicMin)
        self.bpDiastolicMax = try container.decode(Int.self, forKey: .bpDiastolicMax)
        self.glucoseMin = try container.decode(Double.self, forKey: .glucoseMin)
        self.glucoseMax = try container.decode(Double.self, forKey: .glucoseMax)
        self.breakfastTime = try container.decode(TimeOfDay.self, forKey: .breakfastTime)
        self.lunchTime = try container.decode(TimeOfDay.self, forKey: .lunchTime)
        self.dinnerTime = try container.decode(TimeOfDay.self, forKey: .dinnerTime)
        self.bedtimeSlotEnabled = try container.decode(Bool.self, forKey: .bedtimeSlotEnabled)
        self.bpTimes = try container.decode([TimeOfDay].self, forKey: .bpTimes)
        self.bpActiveWeekdaysMask = try container.decode(Int.self, forKey: .bpActiveWeekdaysMask)
        self.enableBeforeMeal = try container.decode(Bool.self, forKey: .enableBeforeMeal)
        self.enableAfterMeal2h = try container.decode(Bool.self, forKey: .enableAfterMeal2h)
        self.enableBedtime = try container.decode(Bool.self, forKey: .enableBedtime)
        self.enableDailyCycleMode = try container.decode(Bool.self, forKey: .enableDailyCycleMode)
        self.currentCycleIndex = try container.decode(Int.self, forKey: .currentCycleIndex)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(glucoseUnit, forKey: .glucoseUnit)
        try container.encode(bpSystolicMin, forKey: .bpSystolicMin)
        try container.encode(bpSystolicMax, forKey: .bpSystolicMax)
        try container.encode(bpDiastolicMin, forKey: .bpDiastolicMin)
        try container.encode(bpDiastolicMax, forKey: .bpDiastolicMax)
        try container.encode(glucoseMin, forKey: .glucoseMin)
        try container.encode(glucoseMax, forKey: .glucoseMax)
        try container.encode(breakfastTime, forKey: .breakfastTime)
        try container.encode(lunchTime, forKey: .lunchTime)
        try container.encode(dinnerTime, forKey: .dinnerTime)
        try container.encode(bedtimeSlotEnabled, forKey: .bedtimeSlotEnabled)
        try container.encode(bpTimes, forKey: .bpTimes)
        try container.encode(bpActiveWeekdaysMask, forKey: .bpActiveWeekdaysMask)
        try container.encode(enableBeforeMeal, forKey: .enableBeforeMeal)
        try container.encode(enableAfterMeal2h, forKey: .enableAfterMeal2h)
        try container.encode(enableBedtime, forKey: .enableBedtime)
        try container.encode(enableDailyCycleMode, forKey: .enableDailyCycleMode)
        try container.encode(currentCycleIndex, forKey: .currentCycleIndex)
    }
}

// MARK: - GoogleIntegration
@Model
public final class GoogleIntegration: Codable, Identifiable {
    public var id: UUID = UUID()
    public var spreadsheetId: String?
    public var googleUserId: String?
    public var refreshToken: String?
    public var isEnabled: Bool = false

    private enum CodingKeys: String, CodingKey {
        case id, spreadsheetId, googleUserId, refreshToken, isEnabled
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.spreadsheetId = try container.decodeIfPresent(String.self, forKey: .spreadsheetId)
        self.googleUserId = try container.decodeIfPresent(String.self, forKey: .googleUserId)
        self.refreshToken = try container.decodeIfPresent(String.self, forKey: .refreshToken)
        self.isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(spreadsheetId, forKey: .spreadsheetId)
        try container.encodeIfPresent(googleUserId, forKey: .googleUserId)
        try container.encodeIfPresent(refreshToken, forKey: .refreshToken)
        try container.encode(isEnabled, forKey: .isEnabled)
    }

    public init(
        id: UUID = UUID(),
        spreadsheetId: String? = nil,
        googleUserId: String? = nil,
        refreshToken: String? = nil,
        isEnabled: Bool = false
    ) {
        self.id = id
        self.spreadsheetId = spreadsheetId
        self.googleUserId = googleUserId
        self.refreshToken = refreshToken
        self.isEnabled = isEnabled
    }
}

