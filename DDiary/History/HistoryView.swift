import SwiftUI
import Observation

struct HistoryView: View {
    @Environment(\.appContainer) private var container
    @State private var viewModel: HistoryViewModel? = nil

    var body: some View {
        Group {
            if let vm = viewModel {
                content(for: vm)
            } else {
                ProgressView()
                    .task { await initializeViewModelIfNeeded() }
            }
        }
        .navigationTitle("History")
    }

    @ViewBuilder
    private func content(for vm: HistoryViewModel) -> some View {
        @Bindable var bvm = vm
        VStack(spacing: 12) {
            Picker("Filter", selection: $bvm.selectedFilter) {
                ForEach(HistoryViewModel.Filter.allCases) { f in
                    Text(f.title).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: bvm.selectedFilter) { _, newValue in
                Task { await vm.updateFilter(newValue) }
            }

            HStack {
                Button("Today") { Task { await vm.updateDateRange(HistoryViewModel.defaultRange(.today)) } }
                Button("7 days") { Task { await vm.updateDateRange(HistoryViewModel.defaultRange(.days7)) } }
                Button("30 days") { Task { await vm.updateDateRange(HistoryViewModel.defaultRange(.days30)) } }
                Spacer()
            }
            .buttonStyle(.bordered)

            summarySection(vm)
            listSection(vm)
        }
        .padding()
        .task { await vm.loadHistory() }
    }

    @ViewBuilder
    private func summarySection(_ vm: HistoryViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Summary").font(.headline)
            if vm.selectedFilter == .both || vm.selectedFilter == .bp {
                VStack(alignment: .leading) {
                    Text("BP count: \(vm.bpCount)")
                    if let min = vm.bpSystolicMin, let max = vm.bpSystolicMax, let avg = vm.bpSystolicAvg {
                        Text("SYS min/max/avg: \(min)/\(max)/\(String(format: "%.1f", avg))")
                    }
                    if let min = vm.bpDiastolicMin, let max = vm.bpDiastolicMax, let avg = vm.bpDiastolicAvg {
                        Text("DIA min/max/avg: \(min)/\(max)/\(String(format: "%.1f", avg))")
                    }
                    if let min = vm.pulseMin, let max = vm.pulseMax, let avg = vm.pulseAvg {
                        Text("Pulse min/max/avg: \(min)/\(max)/\(String(format: "%.1f", avg))")
                    }
                }
            }
            if vm.selectedFilter == .both || vm.selectedFilter == .glucose {
                VStack(alignment: .leading) {
                    Text("Glucose count: \(vm.glucoseCount)")
                    if let min = vm.glucoseMin, let max = vm.glucoseMax, let avg = vm.glucoseAvg {
                        Text("Glucose min/max/avg: \(String(format: "%.2f", min))/\(String(format: "%.2f", max))/\(String(format: "%.2f", avg))")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func listSection(_ vm: HistoryViewModel) -> some View {
        List {
            if vm.selectedFilter == .both || vm.selectedFilter == .bp {
                Section("Blood Pressure") {
                    ForEach(vm.bpMeasurements, id: \.id) { m in
                        VStack(alignment: .leading) {
                            Text(dateString(m.timestamp)).font(.subheadline)
                            Text("SYS/DIA: \(m.systolic)/\(m.diastolic)  Pulse: \(m.pulse)")
                            if let c = m.comment, !c.isEmpty { Text(c).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
            if vm.selectedFilter == .both || vm.selectedFilter == .glucose {
                Section("Glucose") {
                    ForEach(vm.glucoseMeasurements, id: \.id) { m in
                        VStack(alignment: .leading) {
                            Text(dateString(m.timestamp)).font(.subheadline)
                            Text("Value: \(String(format: "%.2f", m.value)) \(m.unit.rawValue)")
                            Text("Type: \(m.measurementType.rawValue)  Slot: \(m.mealSlot.rawValue)")
                            if let c = m.comment, !c.isEmpty { Text(c).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func dateString(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df.string(from: date)
    }

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
