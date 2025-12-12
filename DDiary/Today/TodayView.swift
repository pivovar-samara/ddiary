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
        VStack(alignment: .leading, spacing: 16) {
            if vm.isLoading {
                ProgressView("Loading…")
            }
            if let error = vm.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
            }

            // BP Section
            Section("Blood Pressure") {
                ForEach(vm.bpSlots) { slot in
                    Button(action: { vm.onBPSlotTapped(slot) }) {
                        HStack {
                            Circle()
                                .fill(color(for: slot.status))
                                .frame(width: 12, height: 12)
                            Text(slot.displayTime)
                            Spacer()
                            Text(label(for: slot.status))
                                .foregroundStyle(color(for: slot.status))
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            // Glucose Section
            Section("Glucose") {
                ForEach(vm.glucoseSlots) { slot in
                    Button(action: { vm.onGlucoseSlotTapped(slot) }) {
                        HStack {
                            Circle()
                                .fill(color(for: slot.status))
                                .frame(width: 12, height: 12)
                            VStack(alignment: .leading) {
                                Text("\(slot.mealSlot.rawValue.capitalized) — \(slot.measurementType.rawValue)")
                                Text(slot.displayTime)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(label(for: slot.status))
                                .foregroundStyle(color(for: slot.status))
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            Spacer()
        }
        .padding()
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
                VStack(spacing: 16) {
                    Text("BP Quick Entry (stub)")
                    Button("Dismiss") { vm.presentBPQuickEntry = false }
                }
                .padding()
                .navigationTitle("Quick Entry")
            }
        }
        .sheet(isPresented: $vm.presentGlucoseQuickEntry) {
            NavigationStack {
                VStack(spacing: 16) {
                    Text("Glucose Quick Entry (stub)")
                    Button("Dismiss") { vm.presentGlucoseQuickEntry = false }
                }
                .padding()
                .navigationTitle("Quick Entry")
            }
        }
    }

    private func color(for status: SlotStatus) -> Color {
        switch status {
        case .scheduled: return .gray
        case .due: return .orange
        case .missed: return .red
        case .completed: return .green
        }
    }

    private func label(for status: SlotStatus) -> String {
        switch status {
        case .scheduled: return "Scheduled"
        case .due: return "Due"
        case .missed: return "Missed"
        case .completed: return "Done"
        }
    }
}

// A tiny placeholder container to allow TodayView to initialize before Environment is available.
private let containerPlaceholder: AppContainer = .preview

#Preview {
    TodayView()
        .appContainer(.preview)
}
