//
//  GlucoseQuickEntryForm.swift
//  DDiary
//
//  Created by Ilia Khokhlov on 22.12.25.
//

import SwiftUI

@MainActor
public struct GlucoseQuickEntryForm: View {
    @Environment(\.appContainer) private var container

    let mealSlot: MealSlot?
    let measurementType: GlucoseMeasurementType?
    let existingMeasurementId: UUID?

    @State private var valueText: String = ""
    @State private var comment: String = ""
    @State private var isSaving: Bool = false
    @State private var alertMessage: String? = nil
    @State private var unit: GlucoseUnit? = nil
    @State private var showCommentField: Bool = false
    @State private var invalidValue: Bool = false
    @State private var validationMessage: String? = nil
    @State private var unusualConfirmMessage: String? = nil
    @State private var hasAttemptedSave: Bool = false
    @State private var existingMeasurement: GlucoseMeasurement? = nil
    @State private var glucoseMin: Double = GlucoseConstraints.mmolRange.lowerBound
    @State private var glucoseMax: Double = GlucoseConstraints.mmolRange.upperBound
    @FocusState private var isValueFocused: Bool
    @FocusState private var isCommentFocused: Bool

    let onCancel: () -> Void
    let onSaved: () -> Void

    private var isSaveDisabled: Bool {
        if isSaving { return true }
        // Disable only when non-numeric; allow out-of-range to proceed and show inline error on Save
        return parseValue(from: valueText) == nil
    }

    public var body: some View {
        MeasurementInputLayout(
            title: L10n.quickEntryGlucoseTitle,
            showCommentField: $showCommentField,
            commentText: $comment,
            commentFieldAccessibilityId: "quickEntry.glucose.commentField",
            addCommentAccessibilityId: "quickEntry.glucose.addComment",
            isCommentFocused: $isCommentFocused,
            commentFieldAnchorId: "glucose.comment.field"
        ) {
            VStack(alignment: .center, spacing: DS.Spacing.small) {
                HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.small) {
                    TextField(L10n.quickEntryGlucoseValuePlaceholder, text: $valueText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 44, weight: .semibold))
                        .monospacedDigit()
                        .frame(minWidth: 100)
                        .lineLimit(1)
                        .focused($isValueFocused)
                        .autocorrectionDisabled(true)
                        .textInputAutocapitalization(.never)
                        .accessibilityIdentifier("quickEntry.glucose.valueField")
                        .onChange(of: valueText) { oldValue, newValue in
                            // Sanitize input (allow digits and one decimal separator, max 1 fractional digit)
                            let sanitized = sanitizeInput(newValue)
                            if sanitized != newValue {
                                valueText = sanitized
                                return
                            }
                            // Only compute warnings after first save attempt
                            if hasAttemptedSave {
                                if let val = parseValue(from: sanitized) {
                                    let valueInMmol = (unit == .mmolL) ? val : (val / 18.0)
                                    if glucoseRangeMmol.contains(valueInMmol) {
                                        invalidValue = false
                                        validationMessage = nil
                                    } else {
                                        invalidValue = true
                                        validationMessage = rangeMessage(for: unit)
                                    }
                                } else {
                                    invalidValue = false
                                    validationMessage = nil
                                }
                            }
                        }

                    if let unit = unit {
                        Text(unit == .mmolL ? L10n.unitMmolL : L10n.unitMgDL)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("quickEntry.glucose.unitLabel")
                    }
                }

                if invalidValue, let validationMessage {
                    Text(validationMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("quickEntry.glucose.validationMessage")
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L10n.quickEntryActionCancel) { onCancel() }
                    .accessibilityIdentifier("quickEntry.cancel")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(L10n.quickEntryActionSave) { save() }
                    .disabled(isSaveDisabled)
                    .buttonStyle(.borderedProminent)
                    .fontWeight(.semibold)
                    .tint(.accentColor)
                    .accessibilityIdentifier("quickEntry.save")
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(L10n.quickEntryActionDone) {
                    isValueFocused = false
                }
                .accessibilityIdentifier("quickEntry.glucose.toolbar.done")
            }
        }
        .alert(L10n.quickEntryAlertErrorTitle, isPresented: Binding(get: { alertMessage != nil }, set: { _ in alertMessage = nil })) {
            Button(L10n.quickEntryAlertOK, role: .cancel) { }
        } message: {
            Text(alertMessage ?? "")
        }
        .alert(L10n.quickEntryAlertUnusualValuesTitle, isPresented: Binding(get: { unusualConfirmMessage != nil }, set: { _ in unusualConfirmMessage = nil })) {
            Button(L10n.quickEntryActionCancel, role: .cancel) { }
            Button(L10n.quickEntryAlertSaveAnyway, role: .destructive) {
                if let v = parseValue(from: valueText) {
                    performSaveGlucose(value: v)
                }
            }
        } message: {
            Text(unusualConfirmMessage ?? "")
        }
        .task {
            await loadSettings()
            await prefillIfEditing()
            // Autofocus on appear; keep field neutral until Save is tapped
            isValueFocused = true
        }
    }

    private func title(for type: GlucoseMeasurementType) -> String {
        switch type {
        case .beforeMeal: return L10n.settingsRowBeforeMeal
        case .afterMeal2h: return L10n.settingsRowAfterMeal2h
        case .bedtime: return L10n.settingsRowBedtime
        }
    }

    // MARK: - Validation helpers
    private func sanitizeInput(_ text: String) -> String {
        // Normalize decimal separator to "." and allow only digits and one "."
        var t = text.replacingOccurrences(of: ",", with: ".")
        t = t.filter { ("0123456789.").contains($0) }
        if let dotIndex = t.firstIndex(of: ".") {
            // Keep first dot, remove any subsequent dots and limit to 1 fractional digit
            let intPart = String(t[..<dotIndex])
            let fracStart = t.index(after: dotIndex)
            var fracPart = String(t[fracStart...]).replacingOccurrences(of: ".", with: "")
            if fracPart.count > 1 { fracPart = String(fracPart.prefix(1)) }
            t = intPart + "." + fracPart
        }
        if t.count > GlucoseConstraints.inputMaxLength {
            t = String(t.prefix(GlucoseConstraints.inputMaxLength))
        }
        return t
    }

    private func parseValue(from text: String) -> Double? {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    private func formattedRange(for unit: GlucoseUnit?) -> (low: String, high: String) {
        let isMmol = (unit == .mmolL)
        let low = glucoseRangeMmol.lowerBound * (isMmol ? 1.0 : 18.0)
        let high = glucoseRangeMmol.upperBound * (isMmol ? 1.0 : 18.0)
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = isMmol ? 1 : 0
        formatter.maximumFractionDigits = isMmol ? 1 : 0
        let lowStr = formatter.string(from: NSNumber(value: low)) ?? (isMmol ? String(format: "%.1f", low) : String(format: "%.0f", low))
        let highStr = formatter.string(from: NSNumber(value: high)) ?? (isMmol ? String(format: "%.1f", high) : String(format: "%.0f", high))
        return (lowStr, highStr)
    }

    private func rangeMessage(for unit: GlucoseUnit?) -> String {
        let r = formattedRange(for: unit)
        return L10n.quickEntryMinMax(min: r.low, max: r.high)
    }

    @MainActor
    private func loadSettings() async {
        do {
            let settings = try await container.settingsRepository.getOrCreate()
            unit = settings.glucoseUnit
            glucoseMin = settings.glucoseMin
            glucoseMax = settings.glucoseMax
        } catch {
            unit = .mmolL
        }
    }

    private func prefillIfEditing() async {
        guard let id = existingMeasurementId else { return }
        do {
            if let m = try await container.measurementsRepository.glucoseMeasurement(id: id) {
                self.existingMeasurement = m
                self.valueText = String(format: m.unit == .mmolL ? "%.1f" : "%.0f", m.value)
                self.comment = m.comment ?? ""
                self.showCommentField = !(m.comment ?? "").isEmpty
                self.unit = m.unit
            }
        } catch {
            // Ignore; leave as new entry
        }
    }

    private func save() {
        hasAttemptedSave = true
        // Only guard against non-numeric (Save button is disabled in that case)
        guard let value = parseValue(from: valueText) else { return }

        // Build warning if out of expected range
        let valueInMmol = (unit == .mmolL) ? value : (value / 18.0)
        if !glucoseRangeMmol.contains(valueInMmol) {
            unusualConfirmMessage = L10n.quickEntryGlucoseWarning(rangeMessage(for: unit))
            invalidValue = true
            validationMessage = rangeMessage(for: unit)
            return
        }

        performSaveGlucose(value: value)
    }

    private func performSaveGlucose(value: Double) {
        guard let ms = mealSlot, let mt = measurementType else { return }
        isSaving = true
        Task {
            do {
                if let existing = existingMeasurement, let unit = self.unit {
                    try await container.updateGlucoseMeasurementUseCase.execute(
                        measurement: existing,
                        value: value,
                        unit: unit,
                        measurementType: mt,
                        mealSlot: ms,
                        comment: comment.isEmpty ? nil : comment
                    )
                } else {
                    try await container.logGlucoseMeasurementUseCase.execute(
                        value: value,
                        measurementType: mt,
                        mealSlot: ms,
                        comment: comment.isEmpty ? nil : comment
                    )
                }
                NotificationCenter.default.post(name: .measurementsDidChange, object: nil)
                #if canImport(UIKit)
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                #endif
                onSaved()
            } catch {
                alertMessage = (error as? LocalizedError)?.errorDescription ?? L10n.quickEntryErrorSaveFailed
            }
            isSaving = false
        }
    }

    private var glucoseRangeMmol: ClosedRange<Double> {
        let low = Swift.min(glucoseMin, glucoseMax)
        let high = Swift.max(glucoseMin, glucoseMax)
        guard low > 0, high > 0 else { return GlucoseConstraints.mmolRange }
        return low...high
    }
}
