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

// A tiny placeholder container to allow TodayView to initialize before Environment is available.
private let containerPlaceholder: AppContainer = .preview

#Preview {
    TodayView()
        .appContainer(.preview)
}

