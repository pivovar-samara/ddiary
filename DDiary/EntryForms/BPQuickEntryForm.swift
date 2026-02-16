//
//  BPQuickEntryForm.swift
//  DDiary
//
//  Created by Ilia Khokhlov on 22.12.25.
//

import SwiftUI

@MainActor
public struct BPQuickEntryForm: View {
    @Environment(\.appContainer) private var container

    let existingMeasurementId: UUID?

    @State private var systolicText: String = ""
    @State private var diastolicText: String = ""
    @State private var pulseText: String = ""
    @State private var comment: String = ""
    @State private var showCommentField: Bool = false
    @State private var alertMessage: String? = nil
    @State private var validationMessage: String? = nil
    @State private var invalidFields: Set<Field> = []
    @State private var unusualConfirmMessage: String? = nil
    @State private var hasAttemptedSave: Bool = false
    @State private var existingMeasurement: BPMeasurement? = nil
    @State private var bpSystolicMin: Int = BPConstraints.systolicRange.lowerBound
    @State private var bpSystolicMax: Int = BPConstraints.systolicRange.upperBound
    @State private var bpDiastolicMin: Int = BPConstraints.diastolicRange.lowerBound
    @State private var bpDiastolicMax: Int = BPConstraints.diastolicRange.upperBound
    @State private var bpPulseMin: Int = BPConstraints.pulseRange.lowerBound
    @State private var bpPulseMax: Int = BPConstraints.pulseRange.upperBound

    @FocusState private var focusedField: Field?
    @FocusState private var isCommentFocused: Bool
    private enum Field: Hashable { case systolic, diastolic, pulse }

    let onCancel: () -> Void
    let onSaved: () -> Void

    private var isSaveDisabled: Bool {
        if isSaving { return true }
        // Allow save attempt when numeric but out of range; disable only when non-numeric
        return Int(systolicText) == nil || Int(diastolicText) == nil || Int(pulseText) == nil
    }

    @State private var isSaving: Bool = false

    public var body: some View {
        MeasurementInputLayout(
            title: nil,
            showCommentField: $showCommentField,
            commentText: $comment,
            commentFieldAccessibilityId: "quickEntry.bp.commentField",
            addCommentAccessibilityId: "quickEntry.bp.addComment",
            isCommentFocused: $isCommentFocused,
            commentFieldAnchorId: "bp.comment.field"
        ) {
            // Horizontal, equal-width fields
            HStack(spacing: DS.Spacing.small) {
                fieldColumn(
                    title: L10n.quickEntryBpFieldSystolic,
                    text: $systolicText,
                    field: .systolic,
                    minDigitsToAdvance: 3
                )
                fieldColumn(
                    title: L10n.quickEntryBpFieldDiastolic,
                    text: $diastolicText,
                    field: .diastolic,
                    minDigitsToAdvance: 2
                )
                fieldColumn(
                    title: L10n.quickEntryBpFieldPulse,
                    text: $pulseText,
                    field: .pulse,
                    minDigitsToAdvance: 0
                )
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
                if focusedField != nil {
                    Button {
                        switch focusedField {
                        case .diastolic:
                            focusedField = .systolic
                        case .pulse:
                            focusedField = .diastolic
                        case .systolic:
                            break
                        case .none:
                            break
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityIdentifier("quickEntry.bp.toolbar.back")

                    Button {
                        switch focusedField {
                        case .systolic:
                            focusedField = .diastolic
                        case .diastolic:
                            focusedField = .pulse
                        case .pulse:
                            break
                        case .none:
                            break
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .accessibilityIdentifier("quickEntry.bp.toolbar.next")
                }
            }
            ToolbarItemGroup(placement: .keyboard) {
                if focusedField != nil {
                    Spacer()
                    Button(L10n.quickEntryActionDone) {
                        focusedField = nil
                    }
                    .accessibilityIdentifier("quickEntry.bp.toolbar.done")
                }
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
                // Proceed with current parsed values if possible
                if let sys = Int(systolicText), let dia = Int(diastolicText), let pulse = Int(pulseText) {
                    performSaveBP(sys: sys, dia: dia, pulse: pulse)
                }
            }
        } message: {
            Text(unusualConfirmMessage ?? "")
        }
        .task {
            await loadThresholds()
            await prefillIfEditing()
            // Autofocus SYS on appear for fast entry
            focusedField = .systolic
        }
    }

    // MARK: - Field column builder
    @ViewBuilder
    private func fieldColumn(title: String, text: Binding<String>, field: Field, minDigitsToAdvance: Int) -> some View {
        let isInvalid = invalidFields.contains(field)
        VStack(alignment: .center, spacing: DS.Spacing.medium) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("0", text: text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(fieldFont(field))
                .monospacedDigit()
                .focused($focusedField, equals: field)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier(accessibilityId(for: field))
                .onChange(of: text.wrappedValue) { oldValue, newValue in
                    // Enforce digits-only and max 3 digits to prevent UI overflow
                    let filtered = newValue.filter { $0.isNumber }
                    let capped = String(filtered.prefix(3))
                    if capped != newValue {
                        text.wrappedValue = capped
                        return
                    }

                    // Only compute warnings after first save attempt
                    if hasAttemptedSave {
                        if let intVal = Int(capped) {
                            switch field {
                            case .systolic:
                                if systolicRange.contains(intVal) { invalidFields.remove(.systolic) } else { invalidFields.insert(.systolic) }
                            case .diastolic:
                                if diastolicRange.contains(intVal) { invalidFields.remove(.diastolic) } else { invalidFields.insert(.diastolic) }
                            case .pulse:
                                if pulseRange.contains(intVal) { invalidFields.remove(.pulse) } else { invalidFields.insert(.pulse) }
                            }
                        } else {
                            invalidFields.remove(field)
                        }
                    }

                    // Advance focus when a valid value is entered (range-based)
                    if let intVal = Int(capped) {
                        switch field {
                        case .systolic where BPConstraints.systolicRange.contains(intVal):
                            focusedField = .diastolic
                        case .diastolic where BPConstraints.diastolicRange.contains(intVal):
                            focusedField = .pulse
                        case .pulse:
                            break
                        default:
                            break
                        }
                    }
                }

            if isInvalid {
                HStack(spacing: DS.Spacing.s8) {
                    Text(L10n.quickEntryBadgeUnusual)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    Text(perFieldWarningMessage(for: field))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func fieldFont(_ field: Field) -> Font {
        return .system(size: 44, weight: .semibold, design: .default)
    }

    private func accessibilityId(for field: Field) -> String {
        switch field {
        case .systolic: return "quickEntry.bp.systolicField"
        case .diastolic: return "quickEntry.bp.diastolicField"
        case .pulse: return "quickEntry.bp.pulseField"
        }
    }

    private func perFieldWarningMessage(for field: Field) -> String {
        switch field {
        case .systolic:
            return L10n.quickEntryExpectedRange(min: systolicRange.lowerBound, max: systolicRange.upperBound)
        case .diastolic:
            return L10n.quickEntryExpectedRange(min: diastolicRange.lowerBound, max: diastolicRange.upperBound)
        case .pulse:
            return L10n.quickEntryExpectedRange(min: pulseRange.lowerBound, max: pulseRange.upperBound)
        }
    }

    private func save() {
        hasAttemptedSave = true
        // Parse values; Save remains disabled by UI if non-numeric
        guard let sys = Int(systolicText), let dia = Int(diastolicText), let pulse = Int(pulseText) else { return }

        // Build warnings (out-of-range only)
        var warnings: [String] = []
        if !systolicRange.contains(sys) {
            warnings.append(
                L10n.quickEntryFieldExpected(
                    L10n.quickEntryBpFieldSystolic,
                    min: systolicRange.lowerBound,
                    max: systolicRange.upperBound
                )
            )
        }
        if !diastolicRange.contains(dia) {
            warnings.append(
                L10n.quickEntryFieldExpected(
                    L10n.quickEntryBpFieldDiastolic,
                    min: diastolicRange.lowerBound,
                    max: diastolicRange.upperBound
                )
            )
        }
        if !pulseRange.contains(pulse) {
            warnings.append(
                L10n.quickEntryFieldExpected(
                    L10n.quickEntryBpFieldPulse,
                    min: pulseRange.lowerBound,
                    max: pulseRange.upperBound
                )
            )
        }

        if !warnings.isEmpty {
            unusualConfirmMessage = warnings.joined(separator: "\n")
            // Reflect in per-field warnings for immediate visual feedback
            invalidFields = []
            if !systolicRange.contains(sys) { invalidFields.insert(.systolic) }
            if !diastolicRange.contains(dia) { invalidFields.insert(.diastolic) }
            if !pulseRange.contains(pulse) { invalidFields.insert(.pulse) }
            return
        }

        performSaveBP(sys: sys, dia: dia, pulse: pulse)
    }

    private func performSaveBP(sys: Int, dia: Int, pulse: Int) {
        isSaving = true
        Task {
            do {
                if let existing = existingMeasurement {
                    try await container.updateBPMeasurementUseCase.execute(
                        measurement: existing,
                        systolic: sys,
                        diastolic: dia,
                        pulse: pulse,
                        comment: comment.isEmpty ? nil : comment
                    )
                } else {
                    try await container.logBPMeasurementUseCase.execute(
                        systolic: sys,
                        diastolic: dia,
                        pulse: pulse,
                        comment: comment.isEmpty ? nil : comment
                    )
                }
                #if canImport(UIKit)
                if #available(iOS 13.0, *) {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                } else {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                #endif
                onSaved()
            } catch {
                alertMessage = (error as? LocalizedError)?.errorDescription ?? L10n.quickEntryErrorSaveFailed
            }
            isSaving = false
        }
    }

    private func prefillIfEditing() async {
        guard let id = existingMeasurementId else { return }
        do {
            if let m = try await container.measurementsRepository.bpMeasurement(id: id) {
                self.existingMeasurement = m
                self.systolicText = String(m.systolic)
                self.diastolicText = String(m.diastolic)
                self.pulseText = String(m.pulse)
                self.comment = m.comment ?? ""
                self.showCommentField = !(m.comment ?? "").isEmpty
            }
        } catch {
            // Ignore prefill errors; form remains empty for new entry
        }
    }

    private var systolicRange: ClosedRange<Int> {
        normalizedRange(min: bpSystolicMin, max: bpSystolicMax, fallback: BPConstraints.systolicRange)
    }

    private var diastolicRange: ClosedRange<Int> {
        normalizedRange(min: bpDiastolicMin, max: bpDiastolicMax, fallback: BPConstraints.diastolicRange)
    }

    private var pulseRange: ClosedRange<Int> {
        normalizedRange(min: bpPulseMin, max: bpPulseMax, fallback: BPConstraints.pulseRange)
    }

    private func normalizedRange(min: Int, max: Int, fallback: ClosedRange<Int>) -> ClosedRange<Int> {
        let low = Swift.min(min, max)
        let high = Swift.max(min, max)
        guard low > 0, high > 0 else { return fallback }
        return low...high
    }

    @MainActor
    private func loadThresholds() async {
        do {
            let settings = try await container.settingsRepository.getOrCreate()
            bpSystolicMin = settings.bpSystolicMin
            bpSystolicMax = settings.bpSystolicMax
            bpDiastolicMin = settings.bpDiastolicMin
            bpDiastolicMax = settings.bpDiastolicMax
            bpPulseMin = BPConstraints.pulseRange.lowerBound
            bpPulseMax = BPConstraints.pulseRange.upperBound
        } catch {
            // Keep defaults
        }
    }
}
