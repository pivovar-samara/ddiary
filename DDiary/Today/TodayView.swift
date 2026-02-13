import SwiftUI
import Observation
import Combine
#if canImport(UIKit)
import UIKit
#endif

public struct TodayView: View {
    @Environment(\.appContainer) private var container
    @State private var viewModel: TodayViewModel? = nil
    @State private var editingBPMeasurementId: UUID? = nil
    @State private var editingGlucoseMeasurementId: UUID? = nil

    public init() {}

    public var body: some View {
        Group {
            if let vm = viewModel {
                content(for: vm)
            } else {
                ProgressView(L10n.todayLoading)
                    .task { await initializeViewModelIfNeeded() }
            }
        }
    }

    @ViewBuilder
    private func content(for vm: TodayViewModel) -> some View {
        @Bindable var bvm = vm
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DS.Spacing.large, pinnedViews: []) {
                if bvm.isLoading {
                    ProgressView(L10n.todayLoading)
                }
                if let error = bvm.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                }

                // Unified Today blocks
                if !bvm.itemsDue.isEmpty {
                    VStack(alignment: .leading, spacing: DS.Spacing.xSmall) {
                        BlockHeader(L10n.todayBlockNow, emphasis: .prominent)
                            .accessibilityIdentifier("today.block.now")
                        ForEach(bvm.itemsDue) { item in
                            SlotRow(
                                title: item.title,
                                timeText: item.timeText,
                                status: item.status,
                                trailingStatusText: nil,
                                onTap: { handleTap(item, vm: vm) },
                                accessibilityId: "today.row.\(item.kind.rawValue).\(stableId(for: item))",
                                leadingBadgeText: item.kind == .bp ? "BP" : "GLU",
                                titleFontWeight: .semibold,
                                rowVerticalPadding: DS.Spacing.s8
                            )
                        }
                    }
                }

                if !bvm.itemsScheduled.isEmpty {
                    VStack(alignment: .leading, spacing: DS.Spacing.xSmall) {
                        BlockHeader(L10n.todayBlockLater)
                            .accessibilityIdentifier("today.block.later")
                        ForEach(bvm.itemsScheduled) { item in
                            SlotRow(
                                title: item.title,
                                timeText: item.timeText,
                                status: item.status,
                                trailingStatusText: "",
                                onTap: { handleTap(item, vm: vm) },
                                accessibilityId: "today.row.\(item.kind.rawValue).\(stableId(for: item))",
                                leadingBadgeText: item.kind == .bp ? "BP" : "GLU",
                                trailingIsSecondary: true
                            )
                        }
                    }
                }

                if !bvm.itemsMissed.isEmpty {
                    VStack(alignment: .leading, spacing: DS.Spacing.xSmall) {
                        BlockHeader(L10n.todayBlockOverdue)
                            .accessibilityIdentifier("today.block.overdue")
                        ForEach(bvm.itemsMissed) { item in
                            SlotRow(
                                title: item.title,
                                timeText: item.timeText,
                                status: item.status,
                                trailingStatusText: "",
                                onTap: { handleTap(item, vm: vm) },
                                accessibilityId: "today.row.\(item.kind.rawValue).\(stableId(for: item))",
                                leadingBadgeText: item.kind == .bp ? "BP" : "GLU",
                                trailingIsSecondary: true
                            )
                        }
                    }
                }

                if !bvm.itemsCompleted.isEmpty {
                    CompletedDisclosure(title: L10n.todayBlockCompleted) {
                        VStack(alignment: .leading, spacing: DS.Spacing.small) {
                            ForEach(bvm.itemsCompleted) { item in
                                SlotRow(
                                    title: item.title,
                                    timeText: item.timeText,
                                    status: item.status,
                                    trailingStatusText: nil,
                                    onTap: { handleTap(item, vm: vm) },
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
        .accessibilityIdentifier("today.scroll")
        .task {
            await vm.refresh()
        }
        .sheet(isPresented: $bvm.presentBPQuickEntry) {
            NavigationStack {
                BPQuickEntryForm(
                    existingMeasurementId: editingBPMeasurementId,
                    onCancel: {
                        bvm.presentBPQuickEntry = false
                        editingBPMeasurementId = nil
                    },
                    onSaved: {
                        bvm.presentBPQuickEntry = false
                        editingBPMeasurementId = nil
                        Task { await vm.refresh() }
                    }
                )
                .navigationTitle(L10n.todayQuickEntryTitle)
            }
        }
        .sheet(isPresented: $bvm.presentGlucoseQuickEntry) {
            NavigationStack {
                GlucoseQuickEntryForm(
                    mealSlot: vm.selectedGlucoseSlot?.mealSlot,
                    measurementType: vm.selectedGlucoseSlot?.measurementType,
                    existingMeasurementId: editingGlucoseMeasurementId,
                    onCancel: {
                        bvm.presentGlucoseQuickEntry = false
                        editingGlucoseMeasurementId = nil
                    },
                    onSaved: {
                        bvm.presentGlucoseQuickEntry = false
                        editingGlucoseMeasurementId = nil
                        Task { await vm.refresh() }
                    }
                )
                .navigationTitle(L10n.todayQuickEntryTitle)
            }
        }
        .onChange(of: bvm.presentBPQuickEntry) { _, isPresented in
            if !isPresented {
                Task { await vm.refresh() }
            }
        }
        .onChange(of: bvm.presentGlucoseQuickEntry) { _, isPresented in
            if !isPresented {
                Task { await vm.refresh() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .settingsDidSave)) { _ in
            Task { await vm.refresh() }
        }
    }

    @MainActor
    private func initializeViewModelIfNeeded() async {
        if viewModel == nil {
            let vm = TodayViewModel(
                getTodayOverviewUseCase: container.getTodayOverviewUseCase,
                logBPMeasurementUseCase: container.logBPMeasurementUseCase,
                logGlucoseMeasurementUseCase: container.logGlucoseMeasurementUseCase
            )
            self.viewModel = vm
            await vm.refresh()
        }
    }
    
    private func handleTap(_ item: TodayViewModel.TodayItem, vm: TodayViewModel) {
        switch item.payload {
        case .bp(let slot):
            Task { await prepareAndPresentBP(slot: slot, vm: vm) }
        case .glucose(let slot):
            Task { await prepareAndPresentGlucose(slot: slot, vm: vm) }
        }
    }

    @MainActor
    private func prepareAndPresentBP(slot: BPSlotViewModel, vm: TodayViewModel) async {
        editingBPMeasurementId = slot.matchedMeasurementId
        vm.onBPSlotTapped(slot)
    }

    @MainActor
    private func prepareAndPresentGlucose(slot: GlucoseSlotViewModel, vm: TodayViewModel) async {
        editingGlucoseMeasurementId = slot.matchedMeasurementId
        vm.onGlucoseSlotTapped(slot)
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

#Preview {
    TodayView()
        .appContainer(.preview)
}
