import SwiftUI
import Observation
import Combine
#if canImport(UIKit)
import UIKit
#endif

public struct TodayView: View {
    @Environment(\.appContainer) private var container
    @Environment(\.scenePhase) private var scenePhase
    private let isActiveTab: Bool
    @State private var viewModel: TodayViewModel? = nil
    @State private var editingBPMeasurementId: UUID? = nil
    @State private var editingGlucoseMeasurementId: UUID? = nil
    @State private var selectedBPScheduledDate: Date? = nil
    @State private var selectedGlucoseScheduledDate: Date? = nil
    @State private var cycleSwitchDialogItemID: String? = nil

    public init(isActiveTab: Bool = true) {
        self.isActiveTab = isActiveTab
    }

    public var body: some View {
        Group {
            if let vm = viewModel {
                content(for: vm)
            } else {
                ProgressView(L10n.todayLoading)
                    .task { await initializeViewModelIfNeeded() }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, isActiveTab, let vm = viewModel else { return }
            Task { await vm.refreshIfNeeded(reason: .appBecameActive) }
        }
        .onChange(of: isActiveTab) { _, isNowActiveTab in
            guard isNowActiveTab, scenePhase == .active, let vm = viewModel else { return }
            Task { await vm.refreshIfNeeded(reason: .screenBecameVisible) }
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
                            todayItemRow(
                                item,
                                vm: vm,
                                trailingStatusText: nil,
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
                            todayItemRow(
                                item,
                                vm: vm,
                                trailingStatusText: "",
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
                            todayItemRow(
                                item,
                                vm: vm,
                                trailingStatusText: "",
                                trailingIsSecondary: true
                            )
                        }
                    }
                }

                if !bvm.itemsCompleted.isEmpty {
                    CompletedDisclosure(title: L10n.todayBlockCompleted) {
                        VStack(alignment: .leading, spacing: DS.Spacing.small) {
                            ForEach(bvm.itemsCompleted) { item in
                                todayItemRow(
                                    item,
                                    vm: vm,
                                    trailingStatusText: nil,
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(L10n.settingsRowBloodPressure) {
                        presentManualBPQuickEntry(vm: vm)
                    }
                    Button(L10n.settingsRowGlucose) {
                        presentManualGlucoseQuickEntry(vm: vm)
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("today.addMeasurement")
            }
        }
        .sheet(isPresented: $bvm.presentBPQuickEntry) {
            bpQuickEntrySheet(vm: vm)
        }
        .sheet(isPresented: $bvm.presentGlucoseQuickEntry) {
            glucoseQuickEntrySheet(vm: vm)
        }
        .onChange(of: bvm.presentBPQuickEntry) { _, isPresented in
            if !isPresented {
                selectedBPScheduledDate = nil
                Task { await vm.refreshIfNeeded(reason: .quickEntryDismissed) }
            }
        }
        .onChange(of: bvm.presentGlucoseQuickEntry) { _, isPresented in
            if !isPresented {
                selectedGlucoseScheduledDate = nil
                Task { await vm.refreshIfNeeded(reason: .quickEntryDismissed) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .settingsDidSave)) { _ in
            Task { await vm.refreshIfNeeded(reason: .settingsSaved) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .notificationQuickEntryRequested)) { _ in
            Task { @MainActor in
                handleNotificationQuickEntryIfNeeded(vm: vm)
            }
        }
    }

    @ViewBuilder
    private func todayItemRow(
        _ item: TodayViewModel.TodayItem,
        vm: TodayViewModel,
        trailingStatusText: String?,
        titleFontWeight: Font.Weight? = nil,
        rowVerticalPadding: CGFloat = 6,
        trailingIsSecondary: Bool = false
    ) -> some View {
        switch item.payload {
        case .bp:
            baseSlotRow(
                item,
                vm: vm,
                trailingStatusText: trailingStatusText,
                titleFontWeight: titleFontWeight,
                rowVerticalPadding: rowVerticalPadding,
                trailingIsSecondary: trailingIsSecondary
            )
        case .glucose(let slot):
            let targets = vm.cycleSwitchTargets(for: slot)
            if targets.isEmpty {
                baseSlotRow(
                    item,
                    vm: vm,
                    trailingStatusText: trailingStatusText,
                    titleFontWeight: titleFontWeight,
                    rowVerticalPadding: rowVerticalPadding,
                    trailingIsSecondary: trailingIsSecondary
                )
            } else {
                HStack(alignment: .center, spacing: DS.Spacing.xSmall) {
                    baseSlotRow(
                        item,
                        vm: vm,
                        trailingStatusText: trailingStatusText,
                        titleFontWeight: titleFontWeight,
                        rowVerticalPadding: rowVerticalPadding,
                        trailingIsSecondary: trailingIsSecondary
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    cycleSwitchMenu(targets: targets, item: item, vm: vm)
                }
            }
        }
    }

    private func baseSlotRow(
        _ item: TodayViewModel.TodayItem,
        vm: TodayViewModel,
        trailingStatusText: String?,
        titleFontWeight: Font.Weight?,
        rowVerticalPadding: CGFloat,
        trailingIsSecondary: Bool
    ) -> some View {
        SlotRow(
            title: item.title,
            timeText: item.timeText,
            status: item.status,
            trailingStatusText: trailingStatusText,
            onTap: { handleTap(item, vm: vm) },
            accessibilityId: "today.row.\(item.kind.rawValue).\(stableId(for: item))",
            leadingBadgeText: item.kind == .bp ? "BP" : "GLU",
            trailingIsSecondary: trailingIsSecondary,
            titleFontWeight: titleFontWeight,
            rowVerticalPadding: rowVerticalPadding
        )
    }

    private func cycleSwitchMenu(
        targets: [MealSlot],
        item: TodayViewModel.TodayItem,
        vm: TodayViewModel
    ) -> some View {
        let itemID = stableId(for: item)
        let isDialogPresented = Binding(
            get: { cycleSwitchDialogItemID == itemID },
            set: { isPresented in
                if isPresented {
                    cycleSwitchDialogItemID = itemID
                } else if cycleSwitchDialogItemID == itemID {
                    cycleSwitchDialogItemID = nil
                }
            }
        )

        return Button {
            guard !targets.isEmpty else { return }
            cycleSwitchDialogItemID = itemID
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .disabled(vm.isSwitchingCycleTarget || targets.isEmpty)
        .confirmationDialog(
            "",
            isPresented: isDialogPresented,
            titleVisibility: .hidden
        ) {
            ForEach(targets, id: \.rawValue) { target in
                Button(L10n.settingsRowDailyCycleSwitchTo(vm.cycleSlotTitle(target))) {
                    Task { await vm.switchDailyCycleTarget(to: target) }
                }
            }
            Button(L10n.quickEntryActionCancel, role: .cancel) {}
        }
        .accessibilityLabel(L10n.todayCycleSwitchAccessibilityLabel)
        .accessibilityHint(L10n.todayCycleSwitchAccessibilityHint)
        .accessibilityIdentifier("today.row.cycleSwitch.\(stableId(for: item))")
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
                schedulesUpdater: container.updateSchedulesUseCase,
                notificationsRepository: container.notificationsRepository
            )
            self.viewModel = vm
            await vm.refreshIfNeeded(reason: .initialLoad)
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
        let resolvedScheduledDate = vm.presentQuickEntryFromNotification(
            target: request.target,
            scheduledDate: request.scheduledDate
        )
        switch request.target {
        case .bloodPressure:
            selectedBPScheduledDate = resolvedScheduledDate
        case .glucose:
            selectedGlucoseScheduledDate = resolvedScheduledDate
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
        selectedBPScheduledDate = slot.scheduledDate
        vm.onBPSlotTapped(slot)
    }

    @MainActor
    private func prepareAndPresentGlucose(slot: GlucoseSlotViewModel, vm: TodayViewModel) async {
        editingGlucoseMeasurementId = slot.matchedMeasurementId
        selectedGlucoseScheduledDate = slot.scheduledDate
        vm.onGlucoseSlotTapped(slot)
    }

    private func presentManualBPQuickEntry(vm: TodayViewModel) {
        editingBPMeasurementId = nil
        editingGlucoseMeasurementId = nil
        selectedBPScheduledDate = nil
        selectedGlucoseScheduledDate = nil
        vm.selectedGlucoseSlot = nil
        vm.presentGlucoseQuickEntry = false
        vm.presentBPQuickEntry = true
    }

    private func presentManualGlucoseQuickEntry(vm: TodayViewModel) {
        editingBPMeasurementId = nil
        editingGlucoseMeasurementId = nil
        selectedBPScheduledDate = nil
        selectedGlucoseScheduledDate = nil
        vm.presentBPQuickEntry = false
        vm.selectedGlucoseSlot = defaultManualGlucoseSlot(vm: vm)
        vm.presentGlucoseQuickEntry = true
    }

    private func defaultManualGlucoseSlot(vm: TodayViewModel) -> GlucoseSlotViewModel {
        if let closest = vm.glucoseSlots.min(by: {
            abs($0.scheduledDate.timeIntervalSinceNow) < abs($1.scheduledDate.timeIntervalSinceNow)
        }) {
            return closest
        }
        return GlucoseSlotViewModel(
            mealSlot: .none,
            measurementType: .bedtime,
            displayTime: "",
            scheduledDate: Date(),
            status: .due,
            matchedMeasurementId: nil
        )
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
