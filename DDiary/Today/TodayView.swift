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
    @State private var selectedBPScheduledDate: Date? = nil
    @State private var selectedGlucoseScheduledDate: Date? = nil

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

                if bvm.isDailyCycleModeEnabled {
                    HStack(spacing: DS.Spacing.small) {
                        Text(String(localized: "Daily cycle mode", comment: "Today screen cycle mode status title"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            Task { await vm.shiftCycleDayForward() }
                        } label: {
                            HStack(spacing: DS.Spacing.xSmall) {
                                if bvm.isShiftingCycleDay {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                                Text(String(localized: "Shift +1 day", comment: "Action title to move today's daily cycle step to the next day"))
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(bvm.isShiftingCycleDay || bvm.isLoading)
                        .accessibilityIdentifier("today.cycle.shift")
                    }
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
        .sheet(isPresented: $bvm.presentBPQuickEntry) {
            bpQuickEntrySheet(vm: vm)
        }
        .sheet(isPresented: $bvm.presentGlucoseQuickEntry) {
            glucoseQuickEntrySheet(vm: vm)
        }
        .onChange(of: bvm.presentBPQuickEntry) { _, isPresented in
            if !isPresented {
                selectedBPScheduledDate = nil
                Task { await vm.refresh() }
            }
        }
        .onChange(of: bvm.presentGlucoseQuickEntry) { _, isPresented in
            if !isPresented {
                selectedGlucoseScheduledDate = nil
                Task { await vm.refresh() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .settingsDidSave)) { _ in
            Task { await vm.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .notificationQuickEntryRequested)) { _ in
            Task { @MainActor in
                handleNotificationQuickEntryIfNeeded(vm: vm)
            }
        }
    }

    @ViewBuilder
    private func bpQuickEntrySheet(vm: TodayViewModel) -> some View {
        NavigationStack {
            BPQuickEntryForm(
                existingMeasurementId: editingBPMeasurementId,
                plannedScheduledDate: selectedBPScheduledDate,
                onCancel: {
                    vm.presentBPQuickEntry = false
                    editingBPMeasurementId = nil
                    selectedBPScheduledDate = nil
                },
                onSaved: {
                    vm.presentBPQuickEntry = false
                    editingBPMeasurementId = nil
                    selectedBPScheduledDate = nil
                    Task { await vm.refresh() }
                }
            )
            .navigationTitle(L10n.todayQuickEntryTitle)
        }
    }

    @ViewBuilder
    private func glucoseQuickEntrySheet(vm: TodayViewModel) -> some View {
        NavigationStack {
            GlucoseQuickEntryForm(
                mealSlot: vm.selectedGlucoseSlot?.mealSlot,
                measurementType: vm.selectedGlucoseSlot?.measurementType,
                existingMeasurementId: editingGlucoseMeasurementId,
                plannedScheduledDate: selectedGlucoseScheduledDate,
                onCancel: {
                    vm.presentGlucoseQuickEntry = false
                    editingGlucoseMeasurementId = nil
                    selectedGlucoseScheduledDate = nil
                },
                onSaved: {
                    vm.presentGlucoseQuickEntry = false
                    editingGlucoseMeasurementId = nil
                    selectedGlucoseScheduledDate = nil
                    Task { await vm.refresh() }
                }
            )
            .navigationTitle(L10n.todayQuickEntryTitle)
        }
    }

    @MainActor
    private func initializeViewModelIfNeeded() async {
        if viewModel == nil {
            let vm = TodayViewModel(
                getTodayOverviewUseCase: container.getTodayOverviewUseCase,
                logBPMeasurementUseCase: container.logBPMeasurementUseCase,
                logGlucoseMeasurementUseCase: container.logGlucoseMeasurementUseCase,
                rescheduleGlucoseCycleUseCase: container.rescheduleGlucoseCycleUseCase,
                schedulesUpdater: container.updateSchedulesUseCase
            )
            self.viewModel = vm
            await vm.refresh()
            handleNotificationQuickEntryIfNeeded(vm: vm)
        }
    }

    @MainActor
    private func handleNotificationQuickEntryIfNeeded(vm: TodayViewModel) {
        guard let request = NotificationQuickEntryRouter.shared.consumePendingRequest() else { return }
        editingBPMeasurementId = nil
        editingGlucoseMeasurementId = nil
        selectedBPScheduledDate = nil
        selectedGlucoseScheduledDate = nil
        vm.presentQuickEntryFromNotification(target: request.target)
        selectedGlucoseScheduledDate = vm.selectedGlucoseSlot?.scheduledDate
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
        selectedBPScheduledDate = slot.scheduledDate
        vm.onBPSlotTapped(slot)
    }

    @MainActor
    private func prepareAndPresentGlucose(slot: GlucoseSlotViewModel, vm: TodayViewModel) async {
        editingGlucoseMeasurementId = slot.matchedMeasurementId
        selectedGlucoseScheduledDate = slot.scheduledDate
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
