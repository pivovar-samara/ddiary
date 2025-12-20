import SwiftUI
import Observation

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
                                rowVerticalPadding: 8
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

@MainActor
private struct BPQuickEntryForm: View {
    @Environment(\.appContainer) private var container

    @State private var systolicText: String = ""
    @State private var diastolicText: String = ""
    @State private var pulseText: String = ""
    @State private var comment: String = ""
    @State private var isSaving: Bool = false
    @State private var alertMessage: String? = nil

    let onCancel: () -> Void
    let onSaved: () -> Void

    private var isSaveDisabled: Bool {
        Int(systolicText) == nil || Int(diastolicText) == nil || Int(pulseText) == nil || isSaving
    }

    var body: some View {
        Form {
            Section {
                TextField("Systolic", text: $systolicText)
                    .keyboardType(.numberPad)
                    .accessibilityIdentifier("quickEntry.bp.systolicField")
                TextField("Diastolic", text: $diastolicText)
                    .keyboardType(.numberPad)
                    .accessibilityIdentifier("quickEntry.bp.diastolicField")
                TextField("Pulse", text: $pulseText)
                    .keyboardType(.numberPad)
                    .accessibilityIdentifier("quickEntry.bp.pulseField")
                TextField("Comment", text: $comment, axis: .vertical)
                    .accessibilityIdentifier("quickEntry.bp.commentField")
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
                    .accessibilityIdentifier("quickEntry.save")
            }
        }
        .alert("Error", isPresented: Binding(get: { alertMessage != nil }, set: { _ in alertMessage = nil })) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private func save() {
        guard let sys = Int(systolicText),
              let dia = Int(diastolicText),
              let pulse = Int(pulseText) else { return }
        isSaving = true
        Task {
            do {
                try await container.logBPMeasurementUseCase.execute(
                    systolic: sys,
                    diastolic: dia,
                    pulse: pulse,
                    comment: comment.isEmpty ? nil : comment
                )
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

    let onCancel: () -> Void
    let onSaved: () -> Void

    private var isSaveDisabled: Bool {
        Double(valueText) == nil || isSaving
    }

    var body: some View {
        Form {
            if let ms = mealSlot, let mt = measurementType {
                Section {
                    HStack {
                        Text("Context")
                        Spacer()
                        Text("\(ms.rawValue.capitalized) • \(title(for: mt))")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                TextField("Value", text: $valueText)
                    .keyboardType(.decimalPad)
                    .accessibilityIdentifier("quickEntry.glucose.valueField")
                TextField("Comment", text: $comment, axis: .vertical)
                    .accessibilityIdentifier("quickEntry.glucose.commentField")
            }
            if let unit = unit {
                Section {
                    HStack {
                        Text("Unit")
                        Spacer()
                        Text(unit == .mmolL ? "mmol/L" : "mg/dL")
                            .foregroundStyle(.secondary)
                    }
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
                    .accessibilityIdentifier("quickEntry.save")
            }
        }
        .alert("Error", isPresented: Binding(get: { alertMessage != nil }, set: { _ in alertMessage = nil })) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage ?? "")
        }
        .task { await loadUnit() }
    }

    private func title(for type: GlucoseMeasurementType) -> String {
        switch type {
        case .beforeMeal: return String(localized: "Before meal")
        case .afterMeal2h: return String(localized: "After meal (2h)")
        case .bedtime: return String(localized: "Bedtime")
        }
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
        guard let ms = mealSlot, let mt = measurementType, let value = Double(valueText) else { return }
        isSaving = true
        Task {
            do {
                try await container.logGlucoseMeasurementUseCase.execute(
                    value: value,
                    measurementType: mt,
                    mealSlot: ms,
                    comment: comment.isEmpty ? nil : comment
                )
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

