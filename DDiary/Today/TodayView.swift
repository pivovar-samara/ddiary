import SwiftUI
import Observation
#if canImport(UIKit)
import UIKit
#endif

public struct TodayView: View {
    @Environment(\.appContainer) private var container
    @State private var viewModel: TodayViewModel

    public init() {
        _viewModel = State(initialValue: TodayViewModel(
            getTodayOverviewUseCase: GetTodayOverviewUseCase(
                measurementsRepository: containerPlaceholder.measurementsRepository,
                settingsRepository: containerPlaceholder.settingsRepository
            ),
            logBPMeasurementUseCase: containerPlaceholder.logBPMeasurementUseCase,
            logGlucoseMeasurementUseCase: containerPlaceholder.logGlucoseMeasurementUseCase
        ))
    }

    public var body: some View {
        @Bindable var vm = viewModel
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DS.Spacing.large, pinnedViews: []) {
                if vm.isLoading {
                    ProgressView("Loading…")
                }
                if let error = vm.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                }

                // Unified Today blocks
                if !vm.itemsDue.isEmpty {
                    VStack(alignment: .leading, spacing: DS.Spacing.xSmall) {
                        BlockHeader("Now", emphasis: .prominent)
                            .accessibilityIdentifier("today.block.now")
                        ForEach(vm.itemsDue) { item in
                            SlotRow(
                                title: item.title,
                                timeText: item.timeText,
                                status: item.status,
                                trailingStatusText: nil,
                                onTap: { handleTap(item) },
                                accessibilityId: "today.row.\(item.kind.rawValue).\(stableId(for: item))",
                                leadingBadgeText: item.kind == .bp ? "BP" : "GLU",
                                titleFontWeight: .semibold,
                                rowVerticalPadding: DS.Spacing.s8
                            )
                        }
                    }
                }

                if !vm.itemsScheduled.isEmpty {
                    VStack(alignment: .leading, spacing: DS.Spacing.xSmall) {
                        BlockHeader("Later Today")
                            .accessibilityIdentifier("today.block.later")
                        ForEach(vm.itemsScheduled) { item in
                            SlotRow(
                                title: item.title,
                                timeText: item.timeText,
                                status: item.status,
                                trailingStatusText: "",
                                onTap: { handleTap(item) },
                                accessibilityId: "today.row.\(item.kind.rawValue).\(stableId(for: item))",
                                leadingBadgeText: item.kind == .bp ? "BP" : "GLU",
                                trailingIsSecondary: true
                            )
                        }
                    }
                }

                if !vm.itemsMissed.isEmpty {
                    VStack(alignment: .leading, spacing: DS.Spacing.xSmall) {
                        BlockHeader("Overdue")
                            .accessibilityIdentifier("today.block.overdue")
                        ForEach(vm.itemsMissed) { item in
                            SlotRow(
                                title: item.title,
                                timeText: item.timeText,
                                status: item.status,
                                trailingStatusText: "",
                                onTap: { handleTap(item) },
                                accessibilityId: "today.row.\(item.kind.rawValue).\(stableId(for: item))",
                                leadingBadgeText: item.kind == .bp ? "BP" : "GLU",
                                trailingIsSecondary: true
                            )
                        }
                    }
                }

                if !vm.itemsCompleted.isEmpty {
                    CompletedDisclosure(title: "Completed") {
                        VStack(alignment: .leading, spacing: DS.Spacing.small) {
                            ForEach(vm.itemsCompleted) { item in
                                SlotRow(
                                    title: item.title,
                                    timeText: item.timeText,
                                    status: item.status,
                                    trailingStatusText: nil,
                                    onTap: { handleTap(item) },
                                    accessibilityId: "today.row.\(item.kind.rawValue).\(stableId(for: item))",
                                    leadingBadgeText: item.kind == .bp ? "BP" : "GLU",
                                    trailingIsSecondary: true
                                )
                                .opacity(0.6)
                            }
                        }
                    }
                    .accessibilityIdentifier("today.block.completed")
                }

                Spacer(minLength: 0)
            }
            .padding()
        }
        .onAppear {
            _viewModel.wrappedValue = TodayViewModel(
                getTodayOverviewUseCase: container.getTodayOverviewUseCase,
                logBPMeasurementUseCase: container.logBPMeasurementUseCase,
                logGlucoseMeasurementUseCase: container.logGlucoseMeasurementUseCase
            )
            Task { await viewModel.refresh() }
        }
        .sheet(isPresented: $vm.presentBPQuickEntry) {
            NavigationStack {
                BPQuickEntryForm(
                    onCancel: { vm.presentBPQuickEntry = false },
                    onSaved: { vm.presentBPQuickEntry = false }
                )
                .navigationTitle("Quick Entry")
            }
        }
        .sheet(isPresented: $vm.presentGlucoseQuickEntry) {
            NavigationStack {
                GlucoseQuickEntryForm(
                    mealSlot: viewModel.selectedGlucoseSlot?.mealSlot,
                    measurementType: viewModel.selectedGlucoseSlot?.measurementType,
                    onCancel: { vm.presentGlucoseQuickEntry = false },
                    onSaved: { vm.presentGlucoseQuickEntry = false }
                )
                .navigationTitle("Quick Entry")
            }
        }
    }
    
    private func handleTap(_ item: TodayViewModel.TodayItem) {
        switch item.payload {
        case .bp(let slot):
            viewModel.onBPSlotTapped(slot)
        case .glucose(let slot):
            viewModel.onGlucoseSlotTapped(slot)
        }
    }

    private func stableId(for item: TodayViewModel.TodayItem) -> String {
        // Use the UUID to keep it deterministic and stable across renders
        item.id.uuidString
    }
}

private struct BlockHeader: View {
    enum Emphasis { case prominent, neutral }
    let title: String
    let emphasis: Emphasis

    init(_ title: String, emphasis: Emphasis = .neutral) {
        self.title = title
        self.emphasis = emphasis
    }

    var body: some View {
        Text(title)
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}

private struct CompletedDisclosure<Content: View>: View {
    let title: String
    @State private var isExpanded: Bool = false
    let content: () -> Content

    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: DS.Spacing.small) {
                content()
            }
            .padding(.top, DS.Spacing.small)
        } label: {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("today.completedDisclosure")
    }
}

private enum InputCardStyle {
    static var background: Color {
        #if canImport(UIKit)
        Color(uiColor: .secondarySystemBackground)
        #else
        Color.secondary.opacity(0.1)
        #endif
    }

    static func strokeColor(isInvalid: Bool) -> Color {
        isInvalid ? .red : Color.secondary.opacity(0.25)
    }
}

private enum GlucoseConstraints {
    // Range defined in mmol/L, will convert for mg/dL when needed
    static let mmolRange: ClosedRange<Double> = 2.0...33.3
    // Limit input length to avoid layout jumps (e.g., "33.3")
    static let inputMaxLength: Int = 5
}

private struct MeasurementInputLayout<Fields: View>: View {
    let title: String?
    @Binding var showCommentField: Bool
    @Binding var commentText: String
    let commentFieldAccessibilityId: String
    let addCommentAccessibilityId: String
    var isCommentFocused: FocusState<Bool>.Binding
    let commentFieldAnchorId: String
    let fields: Fields

    init(
        title: String? = nil,
        showCommentField: Binding<Bool>,
        commentText: Binding<String>,
        commentFieldAccessibilityId: String,
        addCommentAccessibilityId: String,
        isCommentFocused: FocusState<Bool>.Binding,
        commentFieldAnchorId: String,
        @ViewBuilder fields: () -> Fields
    ) {
        self.title = title
        self._showCommentField = showCommentField
        self._commentText = commentText
        self.commentFieldAccessibilityId = commentFieldAccessibilityId
        self.addCommentAccessibilityId = addCommentAccessibilityId
        self.isCommentFocused = isCommentFocused
        self.commentFieldAnchorId = commentFieldAnchorId
        self.fields = fields()
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: DS.Spacing.medium) {
                    VStack(spacing: DS.Spacing.medium) {
                        if let title {
                            Text(title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        fields
                    }
                    .padding(.top, DS.Spacing.large)
                    .padding(.horizontal)

                    VStack(alignment: .leading, spacing: DS.Spacing.small) {
                        if showCommentField {
                            VStack(alignment: .leading, spacing: DS.Spacing.s8) {
                                TextField("Comment", text: $commentText, axis: .vertical)
                                    .autocorrectionDisabled(false)
                                    .textInputAutocapitalization(.sentences)
                                    .focused(isCommentFocused)
                                    .accessibilityIdentifier(commentFieldAccessibilityId)
                                    .padding(.vertical, 10)
                                Rectangle()
                                    .fill(InputCardStyle.strokeColor(isInvalid: false))
                                    .frame(height: 1)
                            }
                            .id(commentFieldAnchorId)
                        } else {
                            Button {
                                showCommentField = true
                                DispatchQueue.main.async { isCommentFocused.wrappedValue = true }
                            } label: {
                                HStack(spacing: DS.Spacing.s8) {
                                    Image(systemName: "plus.circle")
                                    Text("Add comment")
                                }
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.tint)
                            .accessibilityIdentifier(addCommentAccessibilityId)
                        }
                    }
                    .padding(.top, DS.Spacing.large)
                    .padding(.horizontal)
                }
                .padding(.bottom, DS.Spacing.large * 2)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: isCommentFocused.wrappedValue) { oldValue, newValue in
                if newValue {
                    withAnimation { proxy.scrollTo(commentFieldAnchorId, anchor: .center) }
                }
            }
        }
    }
}

@MainActor
private struct BPQuickEntryForm: View {
    @Environment(\.appContainer) private var container

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

    var body: some View {
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
                    title: "Systolic",
                    text: $systolicText,
                    field: .systolic,
                    minDigitsToAdvance: 3
                )
                fieldColumn(
                    title: "Diastolic",
                    text: $diastolicText,
                    field: .diastolic,
                    minDigitsToAdvance: 2
                )
                fieldColumn(
                    title: "Pulse",
                    text: $pulseText,
                    field: .pulse,
                    minDigitsToAdvance: 0
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { onCancel() }
                    .accessibilityIdentifier("quickEntry.cancel")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
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
                    Button("Done") {
                        focusedField = nil
                    }
                    .accessibilityIdentifier("quickEntry.bp.toolbar.done")
                }
            }
        }
        .alert("Error", isPresented: Binding(get: { alertMessage != nil }, set: { _ in alertMessage = nil })) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage ?? "")
        }
        .alert("Unusual values", isPresented: Binding(get: { unusualConfirmMessage != nil }, set: { _ in unusualConfirmMessage = nil })) {
            Button("Cancel", role: .cancel) { }
            Button("Save anyway", role: .destructive) {
                // Proceed with current parsed values if possible
                if let sys = Int(systolicText), let dia = Int(diastolicText), let pulse = Int(pulseText) {
                    performSaveBP(sys: sys, dia: dia, pulse: pulse)
                }
            }
        } message: {
            Text(unusualConfirmMessage ?? "")
        }
        .task {
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
                                if BPConstraints.systolicRange.contains(intVal) { invalidFields.remove(.systolic) } else { invalidFields.insert(.systolic) }
                            case .diastolic:
                                if BPConstraints.diastolicRange.contains(intVal) { invalidFields.remove(.diastolic) } else { invalidFields.insert(.diastolic) }
                            case .pulse:
                                if BPConstraints.pulseRange.contains(intVal) { invalidFields.remove(.pulse) } else { invalidFields.insert(.pulse) }
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
                    Text("Unusual")
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
            return "Expected \(BPConstraints.systolicRange.lowerBound)–\(BPConstraints.systolicRange.upperBound)"
        case .diastolic:
            return "Expected \(BPConstraints.diastolicRange.lowerBound)–\(BPConstraints.diastolicRange.upperBound)"
        case .pulse:
            return "Expected \(BPConstraints.pulseRange.lowerBound)–\(BPConstraints.pulseRange.upperBound)"
        }
    }

    private func save() {
        hasAttemptedSave = true
        // Parse values; Save remains disabled by UI if non-numeric
        guard let sys = Int(systolicText), let dia = Int(diastolicText), let pulse = Int(pulseText) else { return }

        // Build warnings (out-of-range only)
        var warnings: [String] = []
        if !BPConstraints.systolicRange.contains(sys) {
            warnings.append("Systolic: Expected \(BPConstraints.systolicRange.lowerBound)–\(BPConstraints.systolicRange.upperBound)")
        }
        if !BPConstraints.diastolicRange.contains(dia) {
            warnings.append("Diastolic: Expected \(BPConstraints.diastolicRange.lowerBound)–\(BPConstraints.diastolicRange.upperBound)")
        }
        if !BPConstraints.pulseRange.contains(pulse) {
            warnings.append("Pulse: Expected \(BPConstraints.pulseRange.lowerBound)–\(BPConstraints.pulseRange.upperBound)")
        }

        if !warnings.isEmpty {
            unusualConfirmMessage = warnings.joined(separator: "\n")
            // Reflect in per-field warnings for immediate visual feedback
            invalidFields = []
            if !BPConstraints.systolicRange.contains(sys) { invalidFields.insert(.systolic) }
            if !BPConstraints.diastolicRange.contains(dia) { invalidFields.insert(.diastolic) }
            if !BPConstraints.pulseRange.contains(pulse) { invalidFields.insert(.pulse) }
            return
        }

        performSaveBP(sys: sys, dia: dia, pulse: pulse)
    }

    private func performSaveBP(sys: Int, dia: Int, pulse: Int) {
        isSaving = true
        Task {
            do {
                try await container.logBPMeasurementUseCase.execute(
                    systolic: sys,
                    diastolic: dia,
                    pulse: pulse,
                    comment: comment.isEmpty ? nil : comment
                )
                #if canImport(UIKit)
                if #available(iOS 13.0, *) {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                } else {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                #endif
                onSaved()
            } catch {
                alertMessage = (error as? LocalizedError)?.errorDescription ?? "Failed to save. Please try again."
            }
            isSaving = false
        }
    }
}

@MainActor
private struct GlucoseQuickEntryForm: View {
    @Environment(\.appContainer) private var container

    let mealSlot: MealSlot?
    let measurementType: GlucoseMeasurementType?

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
    @FocusState private var isValueFocused: Bool
    @FocusState private var isCommentFocused: Bool

    let onCancel: () -> Void
    let onSaved: () -> Void

    private var isSaveDisabled: Bool {
        if isSaving { return true }
        // Disable only when non-numeric; allow out-of-range to proceed and show inline error on Save
        return parseValue(from: valueText) == nil
    }

    var body: some View {
        MeasurementInputLayout(
            title: "Glucose",
            showCommentField: $showCommentField,
            commentText: $comment,
            commentFieldAccessibilityId: "quickEntry.glucose.commentField",
            addCommentAccessibilityId: "quickEntry.glucose.addComment",
            isCommentFocused: $isCommentFocused,
            commentFieldAnchorId: "glucose.comment.field"
        ) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.small) {
                TextField("Value", text: $valueText)
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
                                if GlucoseConstraints.mmolRange.contains(valueInMmol) {
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
                    Text(unit == .mmolL ? "mmol/L" : "mg/dL")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("quickEntry.glucose.unitLabel")
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { onCancel() }
                    .accessibilityIdentifier("quickEntry.cancel")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(isSaveDisabled)
                    .buttonStyle(.borderedProminent)
                    .fontWeight(.semibold)
                    .tint(.accentColor)
                    .accessibilityIdentifier("quickEntry.save")
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    isValueFocused = false
                }
                .accessibilityIdentifier("quickEntry.glucose.toolbar.done")
            }
        }
        .alert("Error", isPresented: Binding(get: { alertMessage != nil }, set: { _ in alertMessage = nil })) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage ?? "")
        }
        .alert("Unusual values", isPresented: Binding(get: { unusualConfirmMessage != nil }, set: { _ in unusualConfirmMessage = nil })) {
            Button("Cancel", role: .cancel) { }
            Button("Save anyway", role: .destructive) {
                if let v = parseValue(from: valueText) {
                    performSaveGlucose(value: v)
                }
            }
        } message: {
            Text(unusualConfirmMessage ?? "")
        }
        .task {
            await loadUnit()
            // Autofocus on appear; keep field neutral until Save is tapped
            isValueFocused = true
        }
    }

    private func title(for type: GlucoseMeasurementType) -> String {
        switch type {
        case .beforeMeal: return String(localized: "Before meal")
        case .afterMeal2h: return String(localized: "After meal (2h)")
        case .bedtime: return String(localized: "Bedtime")
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
        let low = GlucoseConstraints.mmolRange.lowerBound * (isMmol ? 1.0 : 18.0)
        let high = GlucoseConstraints.mmolRange.upperBound * (isMmol ? 1.0 : 18.0)
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = isMmol ? 1 : 0
        formatter.maximumFractionDigits = isMmol ? 1 : 0
        let lowStr = formatter.string(from: NSNumber(value: low)) ?? (isMmol ? String(format: "%.1f", low) : String(format: "%.0f", low))
        let highStr = formatter.string(from: NSNumber(value: high)) ?? (isMmol ? String(format: "%.1f", high) : String(format: "%.0f", high))
        return (lowStr, highStr)
    }

    private func rangeMessage(for unit: GlucoseUnit?) -> String {
        let r = formattedRange(for: unit)
        return "Min \(r.low) / Max \(r.high)"
    }

    @MainActor
    private func loadUnit() async {
        do {
            let settings = try await container.settingsRepository.getOrCreate()
            unit = settings.glucoseUnit
        } catch {
            unit = .mmolL
        }
    }

    private func save() {
        hasAttemptedSave = true
        // Only guard against non-numeric (Save button is disabled in that case)
        guard let value = parseValue(from: valueText) else { return }

        // Build warning if out of expected range
        let valueInMmol = (unit == .mmolL) ? value : (value / 18.0)
        if !GlucoseConstraints.mmolRange.contains(valueInMmol) {
            unusualConfirmMessage = "Glucose: \(rangeMessage(for: unit))"
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
                try await container.logGlucoseMeasurementUseCase.execute(
                    value: value,
                    measurementType: mt,
                    mealSlot: ms,
                    comment: comment.isEmpty ? nil : comment
                )
                #if canImport(UIKit)
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                #endif
                onSaved()
            } catch {
                alertMessage = (error as? LocalizedError)?.errorDescription ?? "Failed to save. Please try again."
            }
            isSaving = false
        }
    }
}

// A tiny placeholder container to allow TodayView to initialize before Environment is available.
private let containerPlaceholder: AppContainer = .preview

#Preview {
    TodayView()
        .appContainer(.preview)
}

