//
//  Models.swift
//  DDiary
//
//  Created by Ilia Khokhlov on 02.12.25.
//

import Foundation
import SwiftData

// MARK: - Enums

public enum GlucoseUnit: String, Codable, Sendable, CaseIterable {
    case mmolL   // mmol/L
    case mgdL    // mg/dL
}

public enum GlucoseMeasurementType: String, Codable, Sendable, CaseIterable {
    case beforeMeal
    case afterMeal2h
    case bedtime
}

public enum MealSlot: String, Codable, Sendable, CaseIterable {
    case breakfast
    case lunch
    case dinner
    case none     // for bedtime or other non-meal cases
}

public enum GoogleSyncStatus: String, Codable, Sendable, CaseIterable {
    case pending
    case success
    case failed
}

// MARK: - Models

struct TimeOfDay: Codable, Hashable, Sendable {
    var hour: Int
    var minute: Int

    init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }
}

extension TimeOfDay {
    func dateComponents(calendar: Calendar = .current) -> DateComponents {
        DateComponents(calendar: calendar, hour: hour, minute: minute)
    }

    static func from(_ components: DateComponents) -> TimeOfDay {
        TimeOfDay(hour: components.hour ?? 0, minute: components.minute ?? 0)
    }
}

@Model
public final class BPMeasurement {
    public var id: UUID = UUID()
    var timestamp: Date = Date()
    var systolic: Int = 0
    var diastolic: Int = 0
    var pulse: Int = 0
    var comment: String?
    var googleSyncStatus: GoogleSyncStatus = GoogleSyncStatus.pending
    var googleLastError: String?
    var googleLastSyncAt: Date?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        systolic: Int,
        diastolic: Int,
        pulse: Int,
        comment: String? = nil,
        googleSyncStatus: GoogleSyncStatus = .pending,
        googleLastError: String? = nil,
        googleLastSyncAt: Date? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.systolic = systolic
        self.diastolic = diastolic
        self.pulse = pulse
        self.comment = comment
        self.googleSyncStatus = googleSyncStatus
        self.googleLastError = googleLastError
        self.googleLastSyncAt = googleLastSyncAt
    }
}

@Model
public final class GlucoseMeasurement {
    public var id: UUID = UUID()
    var timestamp: Date = Date()
    var value: Double = 0.0
    var unit: GlucoseUnit = GlucoseUnit.mmolL
    var measurementType: GlucoseMeasurementType = GlucoseMeasurementType.beforeMeal
    var mealSlot: MealSlot = MealSlot.none
    var comment: String?
    var googleSyncStatus: GoogleSyncStatus = GoogleSyncStatus.pending
    var googleLastError: String?
    var googleLastSyncAt: Date?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        value: Double,
        unit: GlucoseUnit,
        measurementType: GlucoseMeasurementType,
        mealSlot: MealSlot,
        comment: String? = nil,
        googleSyncStatus: GoogleSyncStatus = .pending,
        googleLastError: String? = nil,
        googleLastSyncAt: Date? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.value = value
        self.unit = unit
        self.measurementType = measurementType
        self.mealSlot = mealSlot
        self.comment = comment
        self.googleSyncStatus = googleSyncStatus
        self.googleLastError = googleLastError
        self.googleLastSyncAt = googleLastSyncAt
    }
}

@Model
public final class UserSettings {
    public var id: UUID = UserSettings.singletonRecordID
    var singletonKey: String = UserSettings.singletonRecordKey

    var glucoseUnit: GlucoseUnit = GlucoseUnit.mmolL

    var bpSystolicMin: Int = 90
    var bpSystolicMax: Int = 140
    var bpDiastolicMin: Int = 60
    var bpDiastolicMax: Int = 90

    var glucoseMin: Double = 3.9
    var glucoseMax: Double = 7.8

    var breakfastHour: Int = 8
    var breakfastMinute: Int = 0
    var lunchHour: Int = 13
    var lunchMinute: Int = 0
    var dinnerHour: Int = 19
    var dinnerMinute: Int = 0

    var bedtimeSlotEnabled: Bool = false
    var bedtimeHour: Int = 22
    var bedtimeMinute: Int = 0

    var bpTimes: [Int] = []
    var bpActiveWeekdays: Set<Int> = []

    var enableBeforeMeal: Bool = true
    var enableAfterMeal2h: Bool = true
    var enableBedtime: Bool = false

    var enableDailyCycleMode: Bool = false
    var currentCycleIndex: Int = 0

    init(
        id: UUID = UserSettings.singletonRecordID,
        singletonKey: String = UserSettings.singletonRecordKey,
        glucoseUnit: GlucoseUnit,
        bpSystolicMin: Int,
        bpSystolicMax: Int,
        bpDiastolicMin: Int,
        bpDiastolicMax: Int,
        glucoseMin: Double,
        glucoseMax: Double,
        breakfastHour: Int,
        breakfastMinute: Int,
        lunchHour: Int,
        lunchMinute: Int,
        dinnerHour: Int,
        dinnerMinute: Int,
        bedtimeSlotEnabled: Bool,
        bedtimeHour: Int,
        bedtimeMinute: Int,
        bpTimes: [Int],
        bpActiveWeekdays: Set<Int>,
        enableBeforeMeal: Bool,
        enableAfterMeal2h: Bool,
        enableBedtime: Bool,
        enableDailyCycleMode: Bool,
        currentCycleIndex: Int
    ) {
        self.id = id
        self.singletonKey = singletonKey
        self.glucoseUnit = glucoseUnit
        self.bpSystolicMin = bpSystolicMin
        self.bpSystolicMax = bpSystolicMax
        self.bpDiastolicMin = bpDiastolicMin
        self.bpDiastolicMax = bpDiastolicMax
        self.glucoseMin = glucoseMin
        self.glucoseMax = glucoseMax
        self.breakfastHour = breakfastHour
        self.breakfastMinute = breakfastMinute
        self.lunchHour = lunchHour
        self.lunchMinute = lunchMinute
        self.dinnerHour = dinnerHour
        self.dinnerMinute = dinnerMinute
        self.bedtimeSlotEnabled = bedtimeSlotEnabled
        self.bedtimeHour = bedtimeHour
        self.bedtimeMinute = bedtimeMinute
        self.bpTimes = bpTimes
        self.bpActiveWeekdays = bpActiveWeekdays
        self.enableBeforeMeal = enableBeforeMeal
        self.enableAfterMeal2h = enableAfterMeal2h
        self.enableBedtime = enableBedtime
        self.enableDailyCycleMode = enableDailyCycleMode
        self.currentCycleIndex = currentCycleIndex
    }
}

extension UserSettings {
    static let singletonRecordID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let singletonRecordKey = "user-settings-singleton"

    static func `default`() -> UserSettings {
        let bpMorning = 9 * 60
        let bpEvening = 21 * 60

        return UserSettings(
            singletonKey: singletonRecordKey,
            glucoseUnit: .mmolL,
            bpSystolicMin: 90,
            bpSystolicMax: 140,
            bpDiastolicMin: 60,
            bpDiastolicMax: 90,
            glucoseMin: 3.9,
            glucoseMax: 7.8,
            breakfastHour: 8,
            breakfastMinute: 0,
            lunchHour: 13,
            lunchMinute: 0,
            dinnerHour: 19,
            dinnerMinute: 0,
            bedtimeSlotEnabled: false,
            bedtimeHour: 22,
            bedtimeMinute: 0,
            bpTimes: [bpMorning, bpEvening],
            bpActiveWeekdays: Set(1...7),
            enableBeforeMeal: true,
            enableAfterMeal2h: true,
            enableBedtime: false,
            enableDailyCycleMode: false,
            currentCycleIndex: 0
        )
    }
}

@Model
public final class GoogleIntegration {
    public var id: UUID = GoogleIntegration.singletonRecordID
    var singletonKey: String = GoogleIntegration.singletonRecordKey
    var spreadsheetId: String?
    var googleUserId: String?
    var refreshToken: String?
    var isEnabled: Bool = false

    init(
        id: UUID = GoogleIntegration.singletonRecordID,
        singletonKey: String = GoogleIntegration.singletonRecordKey,
        spreadsheetId: String? = nil,
        googleUserId: String? = nil,
        refreshToken: String? = nil,
        isEnabled: Bool = false
    ) {
        self.id = id
        self.singletonKey = singletonKey
        self.spreadsheetId = spreadsheetId
        self.googleUserId = googleUserId
        self.refreshToken = refreshToken
        self.isEnabled = isEnabled
    }
}

extension GoogleIntegration {
    static let singletonRecordID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    static let singletonRecordKey = "google-integration-singleton"
}
