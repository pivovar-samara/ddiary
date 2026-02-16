import SwiftUI
import Observation

struct SettingsView: View {
    @Environment(\.appContainer) private var container
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

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
        .navigationTitle(L10n.settingsTitle)
        .sheet(isPresented: $presentShareSheet, onDismiss: { exportedURL = nil }) {
            if let url = exportedURL {
                ShareLink(item: url) {
                    Label(L10n.settingsShareExportedCSV, systemImage: "square.and.arrow.up")
                }
                .presentationDetents([.medium, .large])
            } else {
                Text(L10n.settingsShareNoFile)
            }
        }
    }

    @ViewBuilder
    private func content(for vm: SettingsViewModel) -> some View {
        @Bindable var bvm = vm
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DS.Spacing.large) {
                // Units
                SettingsSectionCard(title: L10n.settingsSectionUnits) {
                    VStack(spacing: 0) {
                        SettingsRow(title: L10n.settingsRowGlucoseUnit) {
                            Picker("", selection: $bvm.glucoseUnit) {
                                ForEach(GlucoseUnit.allCases, id: \.self) { unit in
                                    Text(label(for: unit)).tag(unit)
                                }
                            }
                            .labelsHidden()
                        }
                    }
                }

                // Meal Times
                SettingsSectionCard(title: L10n.settingsSectionMealTimes) {
                    VStack(spacing: 0) {
                        SettingsRow(title: L10n.settingsRowBreakfast) {
                            MealOffsetEditor(hours: $bvm.breakfastHour, minutes: $bvm.breakfastMinute)
                        }
                        SettingsDivider()
                        SettingsRow(title: L10n.settingsRowLunch) {
                            MealOffsetEditor(hours: $bvm.lunchHour, minutes: $bvm.lunchMinute)
                        }
                        SettingsDivider()
                        SettingsRow(title: L10n.settingsRowDinner) {
                            MealOffsetEditor(hours: $bvm.dinnerHour, minutes: $bvm.dinnerMinute)
                        }
                        SettingsDivider()
                        SettingsRow(title: L10n.settingsRowBedtime) {
                            MealOffsetEditor(hours: $bvm.bedtimeHour, minutes: $bvm.bedtimeMinute)
                        }
                        SettingsDivider()
                        SettingsToggleRow(
                            title: L10n.settingsRowBedtimeSlotEnabled,
                            isOn: $bvm.bedtimeSlotEnabled,
                            toggleAccessibilityId: "settings.bedtimeSlotEnabled"
                        )
                    }
                }

                // Blood Pressure Reminders
                SettingsSectionCard(title: L10n.settingsSectionBPReminders) {
                    VStack(alignment: .leading, spacing: 0) {
                        if bvm.bpTimes.isEmpty {
                            Text(L10n.settingsRowNoTimesConfigured)
                                .foregroundStyle(.secondary)
                                .frame(minHeight: 48)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            SettingsDivider()
                        } else {
                            ForEach(Array(bvm.bpTimes.enumerated()), id: \.offset) { index, minutes in
                                SettingsRow(title: bpTimeLabel(minutes)) {
                                    Button(role: .destructive) {
                                        bvm.bpTimes.remove(at: index)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                }
                                if index < bvm.bpTimes.count - 1 {
                                    SettingsDivider()
                                }
                            }
                            SettingsDivider()
                        }

                        SettingsActionRow(icon: "plus", title: L10n.settingsRowAddTime, role: .none) {
                            // Add a default time (9:00)
                            bvm.bpTimes.append(9 * 60)
                        }

                        SettingsDivider()

                        VStack(alignment: .leading, spacing: DS.Spacing.small) {
                            Text(L10n.settingsRowActiveWeekdays)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            WeekdayGrid(selected: $bvm.bpActiveWeekdays)
                        }
                    }
                }

                // Glucose Reminders
                SettingsSectionCard(title: L10n.settingsSectionGlucoseReminders) {
                    VStack(spacing: 0) {
                        SettingsToggleRow(
                            title: L10n.settingsRowBeforeMeal,
                            isOn: $bvm.enableBeforeMeal,
                            toggleAccessibilityId: "settings.glucose.beforeMeal"
                        )
                        .disabled(bvm.enableDailyCycleMode)
                        SettingsDivider()
                        SettingsToggleRow(
                            title: L10n.settingsRowAfterMeal2h,
                            isOn: $bvm.enableAfterMeal2h,
                            toggleAccessibilityId: "settings.glucose.afterMeal2h"
                        )
                        .disabled(bvm.enableDailyCycleMode)
                        SettingsDivider()
                        SettingsToggleRow(
                            title: L10n.settingsRowBedtimeToggle,
                            isOn: $bvm.enableBedtime,
                            toggleAccessibilityId: "settings.glucose.bedtime"
                        )
                        .disabled(bvm.enableDailyCycleMode)
                        SettingsDivider()
                        SettingsToggleRow(
                            title: L10n.settingsRowDailyCycleMode,
                            isOn: $bvm.enableDailyCycleMode,
                            toggleAccessibilityId: "settings.glucose.dailyCycle"
                        )
                    }
                }

                // Thresholds
                SettingsSectionCard(title: L10n.settingsSectionThresholds) {
                    VStack(alignment: .leading, spacing: DS.Spacing.medium) {
                        VStack(alignment: .leading, spacing: DS.Spacing.small) {
                            Text(L10n.settingsRowBloodPressure)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            VStack(spacing: 0) {
                                SettingsRow(title: L10n.settingsRowSysMin) {
                                    IntValueCapsuleEditor(value: $bvm.bpSystolicMin, range: 50...250, step: 1)
                                }
                                SettingsDivider()
                                SettingsRow(title: L10n.settingsRowSysMax) {
                                    IntValueCapsuleEditor(value: $bvm.bpSystolicMax, range: 50...250, step: 1)
                                }
                                SettingsDivider()
                                SettingsRow(title: L10n.settingsRowDiaMin) {
                                    IntValueCapsuleEditor(value: $bvm.bpDiastolicMin, range: 30...200, step: 1)
                                }
                                SettingsDivider()
                                SettingsRow(title: L10n.settingsRowDiaMax) {
                                    IntValueCapsuleEditor(value: $bvm.bpDiastolicMax, range: 30...200, step: 1)
                                }
                            }
                        }
                        VStack(alignment: .leading, spacing: DS.Spacing.small) {
                            Text(L10n.settingsRowGlucose)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            VStack(spacing: 0) {
                                SettingsRow(title: L10n.settingsRowGlucoseMin) {
                                    DoubleValueCapsuleEditor(value: $bvm.glucoseMin, range: 1.0...30.0, step: 0.1)
                                }
                                SettingsDivider()
                                SettingsRow(title: L10n.settingsRowGlucoseMax) {
                                    DoubleValueCapsuleEditor(value: $bvm.glucoseMax, range: 1.0...30.0, step: 0.1)
                                }
                            }
                        }
                    }
                }

                // Google Sheets Backup
                SettingsSectionCard(title: L10n.settingsSectionGoogleBackup) {
                    VStack(alignment: .leading, spacing: 0) {
                        // Status block (non-interactive)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Circle()
                                    .fill(bvm.isGoogleBusy ? Color.orange : (bvm.isGoogleEnabled ? Color.green : Color.red))
                                    .frame(width: 10, height: 10)
                                Text(bvm.googleSummary)
                                    .font(.body)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Spacer()
                                ProgressView()
                                    .scaleEffect(0.85)
                                    .opacity(bvm.isGoogleBusy ? 1 : 0)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(L10n.settingsPendingFailed(pending: bvm.pendingCount, failed: bvm.failedCount))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                if let last = bvm.lastSyncAt {
                                    Text(L10n.settingsLastSync(dateString(last)))
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text(L10n.settingsLastSyncNone)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            if bvm.isLikelyRestoringFromICloud {
                                HStack(spacing: DS.Spacing.small) {
                                    ProgressView()
                                        .scaleEffect(0.85)
                                    Text(L10n.cloudRestoreSettingsDescription)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        SettingsDivider()

                        if !bvm.isGoogleEnabled {
                            // Primary action when not connected
                            SettingsActionRow(
                                icon: "link",
                                title: L10n.settingsRowConnect,
                                role: .none,
                                showsActivityIndicator: bvm.isGoogleBusy
                            ) {
                                Task {
                                    await vm.connectGoogleAndSync {
                                        await container.syncWithGoogleUseCase.syncPendingMeasurements()
                                    }
                                }
                            }
                            .disabled(bvm.isGoogleBusy)
                        } else {
                            // Primary action when connected
                            SettingsActionRow(
                                icon: "arrow.clockwise",
                                title: L10n.settingsRowSyncNow,
                                role: .none,
                                showsActivityIndicator: bvm.isGoogleBusy
                            ) {
                                Task {
                                    await container.syncWithGoogleUseCase.syncPendingMeasurements()
                                    await vm.refreshSyncStatus()
                                }
                            }
                            .disabled(bvm.isGoogleBusy)
                            SettingsDivider()
                            // Secondary destructive action
                            SettingsActionRow(icon: "xmark.circle", title: L10n.settingsRowDisconnect, role: .destructive) {
                                Task { await vm.disconnectGoogle() }
                            }
                            .disabled(bvm.isGoogleBusy)
                        }
                    }
                }

                // Export
                SettingsSectionCard(title: L10n.settingsSectionExport) {
                    VStack(spacing: 0) {
                        SettingsRow(title: L10n.settingsRowFrom) {
                            DateRowPicker(date: $exportStartDate)
                        }
                        SettingsDivider()
                        SettingsRow(title: L10n.settingsRowTo) {
                            DateRowPicker(date: $exportEndDate)
                        }
                        SettingsDivider()
                        SettingsToggleRow(title: L10n.settingsRowIncludeBP, isOn: $exportIncludeBP)
                        SettingsDivider()
                        SettingsToggleRow(title: L10n.settingsRowIncludeGlucose, isOn: $exportIncludeGlucose)
                        SettingsDivider()
                        SettingsActionRow(icon: "square.and.arrow.up", title: L10n.settingsRowExportCSV, role: .none) {
                            Task {
                                if let url = await vm.exportCSV(from: exportStartDate, to: exportEndDate, includeBP: exportIncludeBP, includeGlucose: exportIncludeGlucose) {
                                    exportedURL = url
                                    presentShareSheet = true
                                }
                            }
                        }
                        .disabled(vm.isExporting)
                        .overlay(alignment: .trailing) {
                            if vm.isExporting { ProgressView().scaleEffect(0.9) }
                        }
                    }
                }

                // Feedback & About
                SettingsSectionCard(title: L10n.settingsSectionFeedbackAbout) {
                    VStack(alignment: .leading, spacing: DS.Spacing.small) {
                        SettingsActionRow(icon: "envelope", title: L10n.settingsRowSendFeedback) {
                            let subject = L10n.settingsFeedbackEmailSubject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                            if let url = URL(string: "mailto:support@example.com?subject=\(subject)") {
                                openURL(url)
                            }
                        }
                        Text(L10n.settingsDisclaimerMedical)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.medium)
            .padding(.vertical, DS.Spacing.large)
        }
        .refreshable {
            await vm.refreshCloudBackedState()
        }
        .onAppear {
            Task { await vm.refreshCloudBackedState() }
        }
        .accessibilityIdentifier("settings.scroll")
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await vm.refreshCloudBackedState() }
        }
        .toolbar {
            Button(L10n.settingsRowSave) {
                Task {
                    await vm.saveSettings()
                }
            }
            .accessibilityIdentifier("settings.save")
        }
        .overlay(alignment: .bottom) {
            if let error = vm.errorMessage {
                Text(error).padding(8).background(.red.opacity(0.2)).clipShape(RoundedRectangle(cornerRadius: 8)).padding()
            }
        }
    }

    @MainActor
    private func initializeViewModelIfNeeded() async {
        if viewModel == nil {
            let vm = SettingsViewModel(
                settingsRepository: container.settingsRepository,
                googleIntegrationRepository: container.googleIntegrationRepository,
                exportCSVUseCase: container.exportCSVUseCase,
                measurementsRepository: container.measurementsRepository,
                googleSheetsClient: container.googleSheetsClient,
                schedulesUpdater: container.updateSchedulesUseCase
            )
            self.viewModel = vm
            await vm.loadSettings()
        }
    }

    private func label(for unit: GlucoseUnit) -> String {
        switch unit { case .mmolL: return L10n.unitMmolL; case .mgdL: return L10n.unitMgDL }
    }

    private func bpTimeLabel(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        return String(format: "%02d:%02d", h, m)
    }

    private func dateString(_ date: Date) -> String {
        return UIFormatters.dateMediumShortTime.string(from: date)
    }
}

// MARK: - Settings Section Helpers

private struct SectionHeader: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.Spacing.medium)
    }
}

private struct SettingsSectionCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.small) {
            SectionHeader(text: title)
            VStack(alignment: .leading, spacing: DS.Spacing.medium) {
                content()
            }
            .cardContainer()
        }
    }
}

private struct SettingsDivider: View {
    @Environment(\.pixelLength) private var pixelLength

    var body: some View {
        Rectangle()
            .fill(Color(uiColor: .separator))
            .frame(height: pixelLength)
    }
}

private struct SettingsRow<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: DS.Spacing.small) {
            Text(title)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: DS.Spacing.small)
            trailing()
        }
        .frame(minHeight: 48)
    }
}

private struct SettingsToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    var toggleAccessibilityId: String? = nil

    var body: some View {
        HStack(spacing: DS.Spacing.small) {
            Text(title)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: DS.Spacing.small)
            toggleView
        }
        .frame(minHeight: 48)
    }

    @ViewBuilder
    private var toggleView: some View {
        if let id = toggleAccessibilityId {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .accessibilityIdentifier(id)
        } else {
            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
    }
}

private struct SettingsActionRow: View {
    let icon: String
    let title: String
    var role: ButtonRole? = nil
    var showsActivityIndicator: Bool = false
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: DS.Spacing.small) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(role == .destructive ? Color.red : Color.secondary)
                    .alignmentGuide(.firstTextBaseline) { d in d[.firstTextBaseline] }
                Text(title)
                    .font(.body)
                    .foregroundStyle(role == .destructive ? Color.red : Color.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                ProgressView()
                    .scaleEffect(0.85)
                    .opacity(showsActivityIndicator ? 1 : 0)
            }
            .frame(minHeight: 48)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

private struct MealOffsetEditor: View {
    @Binding var hours: Int
    @Binding var minutes: Int

    private let hourRange = 0...23
    private let minuteRange = 0...59

    var body: some View {
        HStack(spacing: DS.Spacing.small) {
            // Hours segment
            HStack(spacing: 8) {
                Button(action: { hours = max(hours - 1, hourRange.lowerBound) }) {
                    Image(systemName: "minus")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 28, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Text("\(hours)h")
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                Button(action: { hours = min(hours + 1, hourRange.upperBound) }) {
                    Image(systemName: "plus")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 28, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .frame(height: 44)
            .background(Color(uiColor: .secondarySystemFill))
            .clipShape(Capsule())
            .fixedSize(horizontal: true, vertical: false)

            // Minutes segment
            HStack(spacing: 8) {
                Button(action: { minutes = max(minutes - 1, minuteRange.lowerBound) }) {
                    Image(systemName: "minus")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 28, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Text("\(minutes)m")
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                Button(action: { minutes = min(minutes + 1, minuteRange.upperBound) }) {
                    Image(systemName: "plus")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 28, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .frame(height: 44)
            .background(Color(uiColor: .secondarySystemFill))
            .clipShape(Capsule())
            .fixedSize(horizontal: true, vertical: false)
        }
        .alignmentGuide(.firstTextBaseline) { d in d[.firstTextBaseline] }
    }
}

private struct IntValueCapsuleEditor: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step: Int = 1

    var body: some View {
        HStack(spacing: 8) {
            Button(action: { value = max(value - step, range.lowerBound) }) {
                Image(systemName: "minus")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 28, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text("\(value)")
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            Button(action: { value = min(value + step, range.upperBound) }) {
                Image(systemName: "plus")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 28, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
        .background(Color(uiColor: .secondarySystemFill))
        .clipShape(Capsule())
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct DoubleValueCapsuleEditor: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 0.1

    var body: some View {
        HStack(spacing: 8) {
            Button(action: { value = max(value - step, range.lowerBound) }) {
                Image(systemName: "minus")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 28, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text(String(format: "%.1f", value))
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            Button(action: { value = min(value + step, range.upperBound) }) {
                Image(systemName: "plus")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 28, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
        .background(Color(uiColor: .secondarySystemFill))
        .clipShape(Capsule())
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct DateRowPicker: View {
    @Binding var date: Date

    var body: some View {
        ZStack(alignment: .trailing) {
            // Keep the system DatePicker to preserve native presentation behavior
            DatePicker("", selection: $date, displayedComponents: [.date])
                .labelsHidden()
                .opacity(0.02) // nearly invisible but still hit-testable

            // Custom trailing display (non-interactive)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(date, style: .date)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "calendar")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .allowsHitTesting(false)
        }
        .frame(height: 44)
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
