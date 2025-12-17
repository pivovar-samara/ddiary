import SwiftUI
import Observation

struct SettingsView: View {
    @Environment(\.appContainer) private var container

    @State private var viewModel: SettingsViewModel? = nil

    // Export sheet
    @State private var exportedURL: URL? = nil
    @State private var presentShareSheet: Bool = false

    // Export controls
    @State private var exportStartDate: Date = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var exportEndDate: Date = Date()
    @State private var exportIncludeBP: Bool = true
    @State private var exportIncludeGlucose: Bool = true

    var body: some View {
        Group {
            if let vm = viewModel {
                content(for: vm)
            } else {
                ProgressView()
                    .task { await initializeViewModelIfNeeded() }
            }
        }
        .navigationTitle("Settings")
        .sheet(isPresented: $presentShareSheet, onDismiss: { exportedURL = nil }) {
            if let url = exportedURL {
                ShareLink(item: url) {
                    Label("Exported CSV", systemImage: "square.and.arrow.up")
                }
                .presentationDetents([.medium, .large])
            } else {
                Text("No file")
            }
        }
    }

    @ViewBuilder
    private func content(for vm: SettingsViewModel) -> some View {
        @Bindable var bvm = vm
        Form {
            // Units
            Section("Units") {
                Picker("Glucose Unit", selection: $bvm.glucoseUnit) {
                    ForEach(GlucoseUnit.allCases, id: \.self) { unit in
                        Text(label(for: unit)).tag(unit)
                    }
                }
            }

            // Meal Times
            Section("Meal Times") {
                HStack {
                    Text("Breakfast")
                    Spacer()
                    Stepper(value: $bvm.breakfastHour, in: 0...23) { Text("\(bvm.breakfastHour)h") }
                    Stepper(value: $bvm.breakfastMinute, in: 0...59) { Text("\(bvm.breakfastMinute)m") }
                }
                HStack {
                    Text("Lunch")
                    Spacer()
                    Stepper(value: $bvm.lunchHour, in: 0...23) { Text("\(bvm.lunchHour)h") }
                    Stepper(value: $bvm.lunchMinute, in: 0...59) { Text("\(bvm.lunchMinute)m") }
                }
                HStack {
                    Text("Dinner")
                    Spacer()
                    Stepper(value: $bvm.dinnerHour, in: 0...23) { Text("\(bvm.dinnerHour)h") }
                    Stepper(value: $bvm.dinnerMinute, in: 0...59) { Text("\(bvm.dinnerMinute)m") }
                }
                Toggle("Bedtime slot enabled", isOn: $bvm.bedtimeSlotEnabled)
            }

            // BP Reminders
            Section("Blood Pressure Reminders") {
                VStack(alignment: .leading) {
                    if bvm.bpTimes.isEmpty {
                        Text("No times configured").foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(bvm.bpTimes.enumerated()), id: \.offset) { index, minutes in
                            HStack {
                                Text(bpTimeLabel(minutes))
                                Spacer()
                                Button(role: .destructive) {
                                    bvm.bpTimes.remove(at: index)
                                } label: { Image(systemName: "trash") }
                            }
                        }
                    }
                    Button {
                        // Add a default time (9:00)
                        bvm.bpTimes.append(9 * 60)
                    } label: { Label("Add time", systemImage: "plus") }
                }

                VStack(alignment: .leading) {
                    Text("Active weekdays")
                    WeekdayGrid(selected: $bvm.bpActiveWeekdays)
                }
            }

            // Glucose Reminders
            Section("Glucose Reminders") {
                Toggle("Before meal", isOn: $bvm.enableBeforeMeal)
                Toggle("After meal (2h)", isOn: $bvm.enableAfterMeal2h)
                Toggle("Bedtime", isOn: $bvm.enableBedtime)
                Toggle("Daily cycle mode (1 per day)", isOn: $bvm.enableDailyCycleMode)
            }

            // Thresholds
            Section("Thresholds") {
                VStack(alignment: .leading) {
                    Text("Blood Pressure")
                    HStack {
                        Stepper("SYS min: \(bvm.bpSystolicMin)", value: $bvm.bpSystolicMin, in: 50...250)
                        Stepper("max: \(bvm.bpSystolicMax)", value: $bvm.bpSystolicMax, in: 50...250)
                    }
                    HStack {
                        Stepper("DIA min: \(bvm.bpDiastolicMin)", value: $bvm.bpDiastolicMin, in: 30...200)
                        Stepper("max: \(bvm.bpDiastolicMax)", value: $bvm.bpDiastolicMax, in: 30...200)
                    }
                }
                VStack(alignment: .leading) {
                    Text("Glucose")
                    HStack {
                        Stepper("Min: \(String(format: "%.1f", bvm.glucoseMin))", value: $bvm.glucoseMin, in: 1...30, step: 0.1)
                        Stepper("Max: \(String(format: "%.1f", bvm.glucoseMax))", value: $bvm.glucoseMax, in: 1...30, step: 0.1)
                    }
                }
            }

            // Google Sheets
            Section("Google Sheets Backup") {
                HStack {
                    Circle().fill(bvm.isGoogleEnabled ? Color.green : Color.red).frame(width: 10, height: 10)
                    Text(bvm.googleSummary)
                    Spacer()
                }
                HStack {
                    Button("Connect") { Task { await vm.connectGoogle() } }
                    Button("Disconnect", role: .destructive) { Task { await vm.disconnectGoogle() } }
                }
            }

            // Export
            Section("Export") {
                DatePicker("From", selection: $exportStartDate, displayedComponents: [.date])
                DatePicker("To", selection: $exportEndDate, displayedComponents: [.date])
                Toggle("Include BP", isOn: $exportIncludeBP)
                Toggle("Include Glucose", isOn: $exportIncludeGlucose)
                Button {
                    Task {
                        if let url = await vm.exportCSV(from: exportStartDate, to: exportEndDate, includeBP: exportIncludeBP, includeGlucose: exportIncludeGlucose) {
                            exportedURL = url
                            presentShareSheet = true
                        }
                    }
                } label: {
                    if vm.isExporting { ProgressView() } else { Label("Export CSV", systemImage: "square.and.arrow.up") }
                }
                .disabled(vm.isExporting)
            }

            // Feedback & About
            Section("Feedback & About") {
                Link(destination: URL(string: "mailto:support@example.com?subject=DDiary%20Feedback")!) {
                    Label("Send Feedback", systemImage: "envelope")
                }
                Text("DDiary is not a medical device. Consult your physician for medical advice.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { Task { await vm.loadSettings() } }
        .toolbar {
            Button("Save") {
                Task {
                    await vm.saveSettings()
                    await container.updateSchedulesUseCase.scheduleFromCurrentSettings()
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let error = vm.errorMessage {
                Text(error).padding(8).background(.red.opacity(0.2)).clipShape(RoundedRectangle(cornerRadius: 8)).padding()
            }
        }
    }

    private func initializeViewModelIfNeeded() async {
        if viewModel == nil {
            let vm = SettingsViewModel(
                settingsRepository: container.settingsRepository,
                googleIntegrationRepository: container.googleIntegrationRepository,
                exportCSVUseCase: container.exportCSVUseCase
            )
            self.viewModel = vm
            await vm.loadSettings()
        }
    }

    private func label(for unit: GlucoseUnit) -> String {
        switch unit { case .mmolL: return "mmol/L"; case .mgdL: return "mg/dL" }
    }

    private func bpTimeLabel(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        return String(format: "%02d:%02d", h, m)
    }
}

// MARK: - Weekday Grid Helper

private struct WeekdayGrid: View {
    @Binding var selected: Set<Int>

    private let symbols = Calendar.current.shortWeekdaySymbols // locale-aware

    var body: some View {
        LazyVGrid(columns: Array(repeating: .init(.flexible(), spacing: 8), count: 7), spacing: 8) {
            ForEach(1...7, id: \.self) { weekday in
                let isOn = selected.contains(weekday)
                Button(action: { toggle(weekday) }) {
                    Text(symbols[(weekday - 1) % symbols.count])
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                        .padding(8)
                        .background(isOn ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }

    private func toggle(_ weekday: Int) {
        if selected.contains(weekday) { selected.remove(weekday) } else { selected.insert(weekday) }
    }
}

#Preview {
    NavigationStack { SettingsView() }
        .appContainer(.preview)
}
