import SwiftUI
import Observation

struct HistoryView: View {
    @Environment(\.appContainer) private var container
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel: HistoryViewModel? = nil

    @State private var presentBPQuickEntry: Bool = false
    @State private var presentGlucoseQuickEntry: Bool = false
    @State private var editingBPMeasurementId: UUID? = nil
    @State private var editingGlucoseMeasurementId: UUID? = nil
    @State private var editingGlucoseMealSlot: MealSlot? = nil
    @State private var editingGlucoseMeasurementType: GlucoseMeasurementType? = nil

    var body: some View {
        Group {
            if let vm = viewModel {
                content(for: vm)
            } else {
                ProgressView()
                    .accessibilityIdentifier("history.scroll")
                    .task { await initializeViewModelIfNeeded() }
            }
        }
        .navigationTitle(L10n.screenHistoryTitle)
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, let vm = viewModel else { return }
            Task { await vm.loadHistory() }
        }
    }

    @ViewBuilder
    private func content(for vm: HistoryViewModel) -> some View {
        @Bindable var bvm = vm

        ScrollView {
            LazyVStack(alignment: .leading, spacing: DS.Spacing.large) {
                HistoryControlsBar(
                    selectedFilter: $bvm.selectedFilter,
                    selectedDateRange: vm.selectedDateRange,
                    onFilterChange: { newFilter in Task { await vm.updateFilter(newFilter) } },
                    onRangeChange: { newRange in Task { await vm.updateDateRange(newRange) } }
                )
                if vm.isLoading {
                    ProgressView(L10n.historyLoading)
                }
                if let error = vm.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                }
                summarySection(vm)
                historySection(vm)
                Spacer(minLength: 0)
            }
            .padding()
        }
        .refreshable {
            await vm.loadHistory()
        }
        .onAppear {
            Task { await vm.loadHistory() }
        }
        .accessibilityIdentifier("history.scroll")
        .sheet(isPresented: $presentBPQuickEntry) {
            NavigationStack {
                BPQuickEntryForm(
                    existingMeasurementId: editingBPMeasurementId,
                    onCancel: {
                        presentBPQuickEntry = false
                        editingBPMeasurementId = nil
                    },
                    onSaved: {
                        presentBPQuickEntry = false
                        editingBPMeasurementId = nil
                    }
                )
                .navigationTitle(L10n.historyQuickEntryTitle)
            }
        }
        .sheet(isPresented: $presentGlucoseQuickEntry) {
            NavigationStack {
                GlucoseQuickEntryForm(
                    mealSlot: editingGlucoseMealSlot,
                    measurementType: editingGlucoseMeasurementType,
                    existingMeasurementId: editingGlucoseMeasurementId,
                    onCancel: {
                        presentGlucoseQuickEntry = false
                        editingGlucoseMeasurementId = nil
                        editingGlucoseMealSlot = nil
                        editingGlucoseMeasurementType = nil
                    },
                    onSaved: {
                        presentGlucoseQuickEntry = false
                        editingGlucoseMeasurementId = nil
                        editingGlucoseMealSlot = nil
                        editingGlucoseMeasurementType = nil
                    }
                )
                .navigationTitle(L10n.historyQuickEntryTitle)
            }
        }
        .onChange(of: presentBPQuickEntry) { _, isPresented in
            if !isPresented {
                Task { await vm.loadHistory() }
            }
        }
        .onChange(of: presentGlucoseQuickEntry) { _, isPresented in
            if !isPresented {
                Task { await vm.loadHistory() }
            }
        }
    }

    @ViewBuilder
    private func summarySection(_ vm: HistoryViewModel) -> some View {
        SummaryCard(vm: vm)
            .accessibilityIdentifier("history.summary")
    }

    @ViewBuilder
    private func historySection(_ vm: HistoryViewModel) -> some View {
        let groups = makeDayGroups(vm: vm)
        if groups.isEmpty && !vm.isLoading && vm.errorMessage == nil {
            VStack(alignment: .leading, spacing: DS.Spacing.small) {
                Text(L10n.historyEmptyTitle)
                    .font(.headline)
                Text(L10n.historyEmptyDescription)
                    .foregroundStyle(.secondary)
            }
            .cardContainer()
            .accessibilityIdentifier("history.list")
            .accessibilityElement(children: .contain)
        } else {
            VStack(alignment: .leading, spacing: DS.Spacing.large) {
                ForEach(groups, id: \.day) { group in
                    VStack(alignment: .leading, spacing: DS.Spacing.small) {
                        Text(UIFormatters.dateMedium.string(from: group.day))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: DS.Spacing.small) {
                            ForEach(group.items, id: \.id) { item in
                                switch item {
                                case .bp(let m):
                                    BPHistoryRow(measurement: m, onTap: {
                                        editingBPMeasurementId = m.id
                                        presentBPQuickEntry = true
                                    })
                                case .glucose(let m):
                                    GlucoseHistoryRow(measurement: m, onTap: {
                                        editingGlucoseMeasurementId = m.id
                                        editingGlucoseMealSlot = m.mealSlot
                                        editingGlucoseMeasurementType = m.measurementType
                                        presentGlucoseQuickEntry = true
                                    })
                                }
                            }
                        }
                    }
                }
            }
            .accessibilityIdentifier("history.list")
            .accessibilityElement(children: .contain)
        }
    }

    private enum HistoryItem {
        case bp(BPMeasurement)
        case glucose(GlucoseMeasurement)

        var id: String {
            switch self {
            case .bp(let m): return "bp:\(m.id.uuidString)"
            case .glucose(let m): return "glucose:\(m.id.uuidString)"
            }
        }

        var timestamp: Date {
            switch self {
            case .bp(let m): return m.timestamp
            case .glucose(let m): return m.timestamp
            }
        }
    }

    private struct DayGroup {
        let day: Date
        let items: [HistoryItem]
    }

    private func makeDayGroups(vm: HistoryViewModel) -> [DayGroup] {
        let includeBP = vm.selectedFilter == .both || vm.selectedFilter == .bp
        let includeGlucose = vm.selectedFilter == .both || vm.selectedFilter == .glucose

        var items: [HistoryItem] = []
        if includeBP { items += vm.bpMeasurements.map { .bp($0) } }
        if includeGlucose { items += vm.glucoseMeasurements.map { .glucose($0) } }

        // Sort all items by timestamp descending to ensure stable ordering
        items.sort { $0.timestamp > $1.timestamp }

        let cal = Calendar.current
        var grouped: [Date: [HistoryItem]] = [:]
        for item in items {
            let day = cal.startOfDay(for: item.timestamp)
            grouped[day, default: []].append(item)
        }

        let sortedDays = grouped.keys.sorted(by: >)
        return sortedDays.map { day in
            DayGroup(day: day, items: grouped[day] ?? [])
        }
    }

    private func dateString(_ date: Date) -> String {
        let df = UIFormatters.dateMediumShortTime
        return df.string(from: date)
    }

    @MainActor
    private func initializeViewModelIfNeeded() async {
        if viewModel == nil {
            let vm = HistoryViewModel(
                getHistory: container.getHistoryUseCase,
                initialRange: HistoryViewModel.defaultRange(.days7)
            )
            self.viewModel = vm
            await vm.loadHistory()
        }
    }
}

#Preview {
    NavigationStack { HistoryView() }
        .appContainer(.preview)
}
