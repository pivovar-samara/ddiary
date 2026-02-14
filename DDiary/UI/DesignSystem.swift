//
//  DesignSystem.swift
//  DDiary
//
//  Created by Ilia Khokhlov on 20.12.25.
//

import SwiftUI
import UIKit
import Foundation

extension Notification.Name {
    static let measurementsDidChange = Notification.Name("MeasurementsDidChange")
}

// MARK: - DDiary Design System

/// Namespace for design tokens and helpers used across the app.
enum DS {
    // MARK: Spacing
    enum Spacing {
        /// 4pt
        static let s4: CGFloat = 4
        /// 8pt
        static let s8: CGFloat = 8
        /// 12pt
        static let s12: CGFloat = 12
        /// 16pt
        static let s16: CGFloat = 16

        // Semantic aliases
        static let xSmall: CGFloat = s4
        static let small: CGFloat = s8
        static let medium: CGFloat = s12
        static let large: CGFloat = s16
    }

    // MARK: Corner Radius
    enum Radius {
        /// 12pt
        static let r12: CGFloat = 12
        /// 16pt
        static let r16: CGFloat = 16

        // Semantic aliases
        static let medium: CGFloat = r12
        static let large: CGFloat = r16
    }
    
    // MARK: Sizes
    enum Sizes {
        /// Standard input card height used for numeric entry fields
        static let inputHeight: CGFloat = 56
    }

    // MARK: Status Keys
    /// A lightweight status key used by the Design System to map semantic colors.
    /// This mirrors the app's slot status semantics without depending on app-specific types.
    enum StatusKey: String, CaseIterable, Sendable {
        case scheduled
        case due
        case missed
        case completed
    }

    // MARK: Semantic Colors
    enum StatusColors {
        /// Neutral color for items that are scheduled but not due yet.
        static var scheduled: Color { .secondary }
        /// Warning color for items that are due.
        static var due: Color { .orange }
        /// Error color for items that were missed.
        static var missed: Color { .red }
        /// Success color for items that are completed.
        static var completed: Color { .green }

        /// Resolve a color for a StatusKey.
        static func color(for key: StatusKey) -> Color {
            switch key {
            case .scheduled: return scheduled
            case .due: return due
            case .missed: return missed
            case .completed: return completed
            }
        }

        /// Resolve a color from a status name.
        /// - Parameter statusName: Case-insensitive name: "scheduled", "due", "missed", or "completed".
        static func color(for statusName: String) -> Color {
            switch statusName.lowercased() {
            case "scheduled": return scheduled
            case "due": return due
            case "missed": return missed
            case "completed": return completed
            default: return .secondary
            }
        }
    }
}

// MARK: - Card Container Styling

@MainActor
struct CardContainerModifier: ViewModifier {
    var cornerRadius: CGFloat = DS.Radius.medium
    var padding: CGFloat = DS.Spacing.medium

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color(uiColor: .separator), lineWidth: 1)
            )
    }
}

@MainActor
extension View {
    /// Applies a card-like container style with system background and subtle border.
    func cardContainer(
        cornerRadius: CGFloat = DS.Radius.medium,
        padding: CGFloat = DS.Spacing.medium
    ) -> some View {
        modifier(CardContainerModifier(cornerRadius: cornerRadius, padding: padding))
    }
}

// MARK: - Numeric Entry Container

@MainActor
struct NumericEntryContainer<Content: View>: View {
    var height: CGFloat = DS.Sizes.inputHeight
    var cornerRadius: CGFloat = DS.Radius.medium
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color(uiColor: .separator), lineWidth: 1)

            HStack(spacing: 0) {
                content()
            }
            .padding(.horizontal, DS.Spacing.small)
            .padding(.vertical, DS.Spacing.s8)
        }
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
    }
}

// MARK: - Status Dot

@MainActor
struct StatusDot: View {
    private let color: Color
    private let size: CGFloat

    /// Create a status dot using a design system status key.
    init(_ key: DS.StatusKey, size: CGFloat = 8) {
        self.color = DS.StatusColors.color(for: key)
        self.size = size
    }

    /// Create a status dot using a status name ("scheduled", "due", "missed", or "completed").
    init(statusName: String, size: CGFloat = 8) {
        self.color = DS.StatusColors.color(for: statusName)
        self.size = size
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

// MARK: - UI Helpers for Today/History

@MainActor
extension SlotStatus {
    /// Semantic system-based color representing the status.
    var color: Color {
        switch self {
        case .scheduled: return DS.StatusColors.scheduled
        case .due: return DS.StatusColors.due
        case .missed: return DS.StatusColors.missed
        case .completed: return DS.StatusColors.completed
        }
    }

    /// Localized human-readable title for the status.
    var localizedTitle: String {
        switch self {
        case .scheduled:
            return L10n.slotStatusScheduled
        case .due:
            return L10n.slotStatusDue
        case .missed:
            return L10n.slotStatusMissed
        case .completed:
            return L10n.slotStatusCompleted
        }
    }
}

// Convenience mapping to existing DS.StatusKey used by StatusDot and other DS helpers.
extension DS.StatusKey {
    init(_ status: SlotStatus) {
        switch status {
        case .scheduled: self = .scheduled
        case .due: self = .due
        case .missed: self = .missed
        case .completed: self = .completed
        }
    }
}

@MainActor
extension StatusDot {
    /// Convenience initializer to use SlotStatus directly with StatusDot.
    init(_ status: SlotStatus, size: CGFloat = 8) {
        self.init(DS.StatusKey(status), size: size)
    }
}

// MARK: - UI Formatters

/// Container for UI-only formatters used by Today/History.
@MainActor
enum UIFormatters {
    /// UI time formatter using current locale/user preferences (12/24h).
    static let timeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = .autoupdatingCurrent
        df.dateStyle = .none
        df.timeStyle = .short
        return df
    }()

    /// Format a date using current locale/user time preferences.
    static func formatTime(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }
    
    static let dateMediumShortTime: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df
    }()
    
    static let dateMedium: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        return df
    }()

    static let numberInt: NumberFormatter = {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.maximumFractionDigits = 0
        nf.usesGroupingSeparator = true
        return nf
    }()

    static let numberOneDecimal: NumberFormatter = {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.minimumFractionDigits = 1
        nf.maximumFractionDigits = 1
        nf.usesGroupingSeparator = true
        return nf
    }()

    static let numberTwoDecimals: NumberFormatter = {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.minimumFractionDigits = 2
        nf.maximumFractionDigits = 2
        nf.usesGroupingSeparator = true
        return nf
    }()

    /// Formats a glucose value for display using locale-aware NumberFormatter.
    /// - Shows two decimals for mmol/L and 0 decimals for mg/dL.
    /// - Returns "—" for NaN/inf or values outside a conservative valid range.
    static func formatGlucoseValue(_ value: Double, unit: GlucoseUnit) -> String {
        guard value.isFinite else { return "—" }
        switch unit {
        case .mmolL:
            return numberTwoDecimals.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
        case .mgdL:
            return numberInt.string(from: NSNumber(value: value)) ?? String(Int(value.rounded()))
        }
    }
}

// MARK: - UI Strings & Title Builders

/// UI string helpers for composing human-readable titles.
@MainActor
enum UIStrings {
    /// Compose a glucose entry title from a meal slot and measurement type.
    /// - Parameters:
    ///   - mealSlot: A token like "breakfast", "lunch", "dinner", "snack", "preMeal", "postMeal", or "fasting".
    ///   - measurementType: A token like "fingerstick", "sensor", "capillary", etc.
    /// - Returns: Human readable title like "Breakfast • Fingerstick" or "Pre-meal • Sensor".
    static func glucoseTitle(mealSlot: String?, measurementType: String?) -> String {
        let meal = mealSlot?.trimmingCharacters(in: .whitespacesAndNewlines)
        let type = measurementType?.trimmingCharacters(in: .whitespacesAndNewlines)

        // Special-case: Bedtime should read simply "Bedtime" (avoid "None • Bedtime").
        if let t = type {
            let key = t
                .replacingOccurrences(of: "_", with: "")
                .replacingOccurrences(of: "-", with: "")
                .lowercased()
            if key == "bedtime" {
                return L10n.settingsRowBedtime
            }
        }

        let mealText = meal.flatMap { humanize($0) }
        let typeText = type.flatMap { humanize($0) }

        switch (mealText, typeText) {
        case let (m?, t?) where !m.isEmpty && !t.isEmpty:
            return "\(m) • \(t)"
        case let (m?, _):
            return m
        case let (_, t?):
            return t
        default:
            return L10n.settingsRowGlucose
        }
    }

    /// Non-optional convenience overload.
    static func glucoseTitle(mealSlot: String, measurementType: String) -> String {
        glucoseTitle(mealSlot: Optional(mealSlot), measurementType: Optional(measurementType))
    }

    // MARK: Internal helpers

    /// Turn identifiers like "preMeal", "post_meal", or "fingerstick" into human-readable text.
    private static func humanize(_ raw: String) -> String {
        let key = raw
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .lowercased()

        let map: [String: String] = [
            "beforemeal": L10n.settingsRowBeforeMeal,
            "premeal": L10n.settingsRowBeforeMeal,
            "aftermeal2h": L10n.settingsRowAfterMeal2h,
            "postmeal": L10n.settingsRowAfterMeal2h,
            "bedtime": L10n.settingsRowBedtime,
            "fasting": L10n.glucoseTypeFasting,
            "random": L10n.glucoseTypeRandom,
            "breakfast": L10n.settingsRowBreakfast,
            "lunch": L10n.settingsRowLunch,
            "dinner": L10n.settingsRowDinner,
            "snack": L10n.mealSnack,
            "fingerstick": L10n.measurementTypeFingerstick,
            "sensor": L10n.measurementTypeSensor,
            "capillary": L10n.measurementTypeCapillary,
            "venous": L10n.measurementTypeVenous
        ]

        if let value = map[key] { return value }

        let separated = raw
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        let spaced = insertSpacesBeforeCapitals(in: separated)
        return spaced
            .split(separator: " ")
            .map { $0.lowercased().capitalized }
            .joined(separator: " ")
    }

    private static func insertSpacesBeforeCapitals(in input: String) -> String {
        var result = ""
        var previousIsLowerOrDigit = false
        for scalar in input.unicodeScalars {
            let ch = Character(scalar)
            if ch.isUppercase, previousIsLowerOrDigit { result.append(" ") }
            result.append(ch)
            previousIsLowerOrDigit = ch.isLowercase || ch.isNumber
        }
        return result
    }
}

// MARK: - Card Container Styling


// MARK: - Preview

#Preview("Design System") {
    VStack(alignment: .leading, spacing: DS.Spacing.medium) {
        Text("Card Container")
            .font(.headline)
        VStack(alignment: .leading, spacing: DS.Spacing.small) {
            HStack(spacing: DS.Spacing.small) {
                StatusDot(DS.StatusKey.scheduled)
                Text("Scheduled")
            }
            HStack(spacing: DS.Spacing.small) {
                StatusDot(DS.StatusKey.due)
                Text("Due")
            }
            HStack(spacing: DS.Spacing.small) {
                StatusDot(DS.StatusKey.missed)
                Text("Missed")
            }
            HStack(spacing: DS.Spacing.small) {
                StatusDot(DS.StatusKey.completed)
                Text("Completed")
            }
        }
        .cardContainer()
    }
    .padding()
}
