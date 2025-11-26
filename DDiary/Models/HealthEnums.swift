//
//  HealthEnums.swift
//  DDiary
//
//  Created by Ilia Khokhlov on 26.11.25.
//

import Foundation

// MARK: - Glucose Unit
public enum GlucoseUnit: String, Codable, CaseIterable, Sendable {
    case mmolL
    case mgdL

    public var displayShort: String {
        switch self {
        case .mmolL: return "mmol/L"
        case .mgdL: return "mg/dL"
        }
    }

    // Conversion helpers
    // 1 mmol/L ≈ 18 mg/dL
    public func toMGDL(_ value: Double) -> Double {
        switch self {
        case .mmolL:
            return value * 18.0
        case .mgdL:
            return value
        }
    }

    public func toMMOLL(_ value: Double) -> Double {
        switch self {
        case .mmolL:
            return value
        case .mgdL:
            return value / 18.0
        }
    }
}

// MARK: - Glucose Measurement Type
public enum GlucoseMeasurementType: String, Codable, CaseIterable, Sendable {
    case beforeMeal
    case afterMeal2h
    case bedtime

    public var displayName: String {
        switch self {
        case .beforeMeal: return "Before meal"
        case .afterMeal2h: return "2h after meal"
        case .bedtime: return "Bedtime"
        }
    }
}

// MARK: - Meal Slot
public enum MealSlot: String, Codable, CaseIterable, Sendable {
    case breakfast
    case lunch
    case dinner
    case none

    public var displayName: String {
        switch self {
        case .breakfast: return "Breakfast"
        case .lunch: return "Lunch"
        case .dinner: return "Dinner"
        case .none: return "None"
        }
    }
}

// MARK: - Google Sync Status
public enum GoogleSyncStatus: String, Codable, CaseIterable, Sendable {
    case notSynced
    case queued
    case syncing
    case synced
    case failed

    public var isInProgress: Bool {
        self == .queued || self == .syncing
    }

    public var isError: Bool {
        self == .failed
    }
}
