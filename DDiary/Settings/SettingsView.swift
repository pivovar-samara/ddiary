import SwiftUI
import Observation
import UIKit

struct SettingsView: View {
    @Environment(\.appContainer) private var container
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var viewModel: SettingsViewModel? = nil

    // Export share presentation
    @State private var exportShareItem: ExportShareItem? = nil

    // Export controls
    @State private var exportStartDate: Date = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var exportEndDate: Date = Date()
    @State private var exportIncludeBP: Bool = true
    @State private var exportIncludeGlucose: Bool = true
    @State private var exportDatePickerSheet: ExportDatePickerSheet? = nil
    @State private var isDailyCycleTargetDialogPresented: Bool = false
    @State private var dailyCycleDialogTargets: [MealSlot] = []
    @State private var dailyCycleDialogDate: Date? = nil

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
        .sheet(item: $exportShareItem, onDismiss: { exportShareItem = nil }) { item in
            ActivityShareSheet(activityItems: [item.url])
        }
        .sheet(item: $exportDatePickerSheet) { sheet in
            exportDatePickerSheetContent(for: sheet)
        }
    }

    @ViewBuilder
    private func content(for vm: SettingsViewModel) -> some View {
        @Bindable var bvm = vm
        Form {
            // Units
            SettingsSectionCard(title: L10n.settingsSectionUnits) {
                SettingsRow(title: L10n.settingsRowGlucoseUnit) {
                    Picker("", selection: $bvm.glucoseUnit) {
                        ForEach(GlucoseUnit.allCases, id: \.self) { unit in
                            Text(label(for: unit)).tag(unit)
                        }
                    }
                    .labelsHidden()
                }
            }

            // Meal Times
            SettingsSectionCard(title: L10n.settingsSectionMealTimes) {
                SettingsRow(title: L10n.settingsRowBreakfast) {
                    TimeOfDayPicker(
                        minutesSinceMidnight: mealTimeBinding(
                            hour: $bvm.breakfastHour,
                            minute: $bvm.breakfastMinute
                        )
                    )
                    .accessibilityIdentifier("settings.meal.breakfast")
                }
                SettingsRow(title: L10n.settingsRowLunch) {
                    TimeOfDayPicker(
                        minutesSinceMidnight: mealTimeBinding(
                            hour: $bvm.lunchHour,
                            minute: $bvm.lunchMinute
                        )
                    )
                    .accessibilityIdentifier("settings.meal.lunch")
                }
                SettingsRow(title: L10n.settingsRowDinner) {
                    TimeOfDayPicker(
                        minutesSinceMidnight: mealTimeBinding(
                            hour: $bvm.dinnerHour,
                            minute: $bvm.dinnerMinute
                        )
                    )
                    .accessibilityIdentifier("settings.meal.dinner")
                }
                SettingsRow(title: L10n.settingsRowBedtime) {
                    TimeOfDayPicker(
                        minutesSinceMidnight: mealTimeBinding(
                            hour: $bvm.bedtimeHour,
                            minute: $bvm.bedtimeMinute
                        )
                    )
                    .accessibilityIdentifier("settings.meal.bedtime")
                }
                SettingsToggleRow(
                    title: L10n.settingsRowBedtimeSlotEnabled,
                    isOn: $bvm.bedtimeSlotEnabled,
                    toggleAccessibilityId: "settings.bedtimeSlotEnabled"
                )
            }

            // Blood Pressure Reminders
            SettingsSectionCard(title: L10n.settingsSectionBPReminders) {
                if bvm.bpTimes.isEmpty {
                    Text(L10n.settingsRowNoTimesConfigured)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(bvm.bpTimes.indices), id: \.self) { index in
                        HStack(spacing: DS.Spacing.small) {
                            TimeOfDayPicker(
                                minutesSinceMidnight: Binding(
                                    get: {
                                        guard bvm.bpTimes.indices.contains(index) else { return 9 * 60 }
                                        return bvm.bpTimes[index]
                                    },
                                    set: { newValue in
                                        guard bvm.bpTimes.indices.contains(index) else { return }
                                        bvm.bpTimes[index] = clampedMinutesSinceMidnight(newValue)
                                    }
                                )
                            )
                            .accessibilityIdentifier("settings.bp.time.\(index)")
                            Spacer(minLength: DS.Spacing.small)
                            Button(role: .destructive) {
                                bvm.bpTimes.remove(at: index)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("settings.bp.remove.\(index)")
                        }
                        .frame(minHeight: 38)
                        .settingsCompactRow()
                    }
                }

                SettingsActionRow(icon: "plus", title: L10n.settingsRowAddTime, role: .none) {
                    bvm.bpTimes.append(9 * 60)
                }

                VStack(alignment: .leading, spacing: DS.Spacing.small) {
                    Text(L10n.settingsRowActiveWeekdays)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    WeekdayGrid(selected: $bvm.bpActiveWeekdays)
                }
            }

            // Glucose Reminders
            SettingsSectionCard(title: L10n.settingsSectionGlucoseReminders) {
                SettingsToggleRow(
                    title: L10n.settingsRowBeforeMeal,
                    isOn: $bvm.enableBeforeMeal,
                    toggleAccessibilityId: "settings.glucose.beforeMeal"
                )
                .disabled(bvm.enableDailyCycleMode)
                SettingsToggleRow(
                    title: L10n.settingsRowAfterMeal2h,
                    isOn: $bvm.enableAfterMeal2h,
                    toggleAccessibilityId: "settings.glucose.afterMeal2h"
                )
                .disabled(bvm.enableDailyCycleMode)
                SettingsToggleRow(
                    title: L10n.settingsRowBedtimeToggle,
                    isOn: $bvm.enableBedtime,
                    toggleAccessibilityId: "settings.glucose.bedtime"
                )
                .disabled(bvm.enableDailyCycleMode)
                SettingsToggleRow(
                    title: L10n.settingsRowDailyCycleMode,
                    isOn: $bvm.enableDailyCycleMode,
                    toggleAccessibilityId: "settings.glucose.dailyCycle"
                )
                SettingsRow(title: L10n.settingsRowDailyCycleTodayIs) {
                    HStack(spacing: DS.Spacing.small) {
                        Text(bvm.dailyCycleCurrentSlotTitle)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("settings.glucose.dailyCycle.current")
                        Button {
                            let now = Date()
                            let targets = bvm.dailyCycleSwitchTargets(today: now)
                            guard !targets.isEmpty else { return }
                            dailyCycleDialogTargets = targets
                            dailyCycleDialogDate = now
                            isDailyCycleTargetDialogPresented = true
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                        .disabled(!bvm.enableDailyCycleMode || bvm.isSwitchingCycleTarget || bvm.dailyCycleSwitchTargets().isEmpty)
                        .accessibilityIdentifier("settings.glucose.dailyCycle.switch")
                        .accessibilityLabel(L10n.todayCycleSwitchAccessibilityLabel)
                        .accessibilityHint(L10n.todayCycleSwitchAccessibilityHint)
                        .confirmationDialog(
                            L10n.todayCycleSwitchAccessibilityLabel,
                            isPresented: $isDailyCycleTargetDialogPresented,
                            titleVisibility: .automatic
                        ) {
                            ForEach(dailyCycleDialogTargets, id: \.rawValue) { target in
                                Button(L10n.settingsRowDailyCycleSwitchTo(bvm.cycleSlotTitle(target))) {
                                    let referenceDate = dailyCycleDialogDate ?? Date()
                                    Task { await bvm.applyDailyCycleTarget(target, today: referenceDate) }
                                }
                            }
                            Button(L10n.quickEntryActionCancel, role: .cancel) {}
                        }
                    }
                }
                .disabled(!bvm.enableDailyCycleMode)
            }

            // Thresholds
            SettingsSectionCard(title: L10n.settingsSectionThresholds) {
                ThresholdGroupHeader(title: L10n.settingsRowBloodPressure)
                SettingsRow(title: L10n.settingsRowSysMin) {
                    IntValueCapsuleEditor(value: $bvm.bpSystolicMin, range: 50...250, step: 1)
                }
                SettingsRow(title: L10n.settingsRowSysMax) {
                    IntValueCapsuleEditor(value: $bvm.bpSystolicMax, range: 50...250, step: 1)
                }
                SettingsRow(title: L10n.settingsRowDiaMin) {
                    IntValueCapsuleEditor(value: $bvm.bpDiastolicMin, range: 30...200, step: 1)
                }
                SettingsRow(title: L10n.settingsRowDiaMax) {
                    IntValueCapsuleEditor(value: $bvm.bpDiastolicMax, range: 30...200, step: 1)
                }

                ThresholdGroupHeader(title: L10n.settingsRowGlucose, topPadding: 8)
                SettingsRow(title: L10n.settingsRowGlucoseMin) {
                    DoubleValueCapsuleEditor(
                        value: glucoseThresholdBinding(
                            mmolBinding: $bvm.glucoseMin,
                            vm: vm
                        ),
                        range: vm.glucoseThresholdRangeForCurrentUnit(),
                        step: vm.glucoseThresholdStepForCurrentUnit(),
                        fractionDigits: vm.glucoseUnit == .mmolL ? 1 : 0
                    )
                }
                SettingsRow(title: L10n.settingsRowGlucoseMax) {
                    DoubleValueCapsuleEditor(
                        value: glucoseThresholdBinding(
                            mmolBinding: $bvm.glucoseMax,
                            vm: vm
                        ),
                        range: vm.glucoseThresholdRangeForCurrentUnit(),
                        step: vm.glucoseThresholdStepForCurrentUnit(),
                        fractionDigits: vm.glucoseUnit == .mmolL ? 1 : 0
                    )
                }
            }

            // Google Sheets Backup
            SettingsSectionCard(title: L10n.settingsSectionGoogleBackup) {
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
                .frame(minHeight: 38)
                .settingsCompactRow()

                if !bvm.isGoogleEnabled {
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
                    SettingsActionRow(icon: "xmark.circle", title: L10n.settingsRowDisconnect, role: .destructive) {
                        Task { await vm.disconnectGoogle() }
                    }
                    .disabled(bvm.isGoogleBusy)
                }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.settingsPendingFailed(pending: bvm.pendingCount, failed: bvm.failedCount))
                    if let last = bvm.lastSyncAt {
                        Text(L10n.settingsLastSync(dateTimeString(last)))
                    } else {
                        Text(L10n.settingsLastSyncNone)
                    }
                    if bvm.isLikelyRestoringFromICloud {
                        HStack(spacing: DS.Spacing.small) {
                            ProgressView()
                                .scaleEffect(0.85)
                            Text(L10n.cloudRestoreSettingsDescription)
                        }
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            // Export
            SettingsSectionCard(title: L10n.settingsSectionExport) {
                SettingsRow(title: L10n.settingsRowFrom) {
                    exportDateButton(
                        date: exportStartDate,
                        sheet: .from
                    )
                    .accessibilityIdentifier("settings.export.fromDate")
                }
                SettingsRow(title: L10n.settingsRowTo) {
                    exportDateButton(
                        date: exportEndDate,
                        sheet: .to
                    )
                    .accessibilityIdentifier("settings.export.toDate")
                }
                SettingsToggleRow(title: L10n.settingsRowIncludeBP, isOn: $exportIncludeBP)
                SettingsToggleRow(title: L10n.settingsRowIncludeGlucose, isOn: $exportIncludeGlucose)
                SettingsActionRow(icon: "square.and.arrow.up", title: L10n.settingsRowExportCSV, role: .none) {
                    Task {
                        if let url = await vm.exportCSV(from: exportStartDate, to: exportEndDate, includeBP: exportIncludeBP, includeGlucose: exportIncludeGlucose) {
                            exportShareItem = ExportShareItem(url: url)
                        }
                    }
                }
                .disabled(vm.isExporting)
                .overlay(alignment: .trailing) {
                    if vm.isExporting { ProgressView().scaleEffect(0.9) }
                }
            }

            // Feedback & About
            SettingsSectionCard(title: L10n.settingsSectionFeedbackAbout) {
                SettingsActionRow(icon: "envelope", title: L10n.settingsRowSendFeedback) {
                    if let url = feedbackEmailURL() {
                        openURL(url)
                    }
                }
                .disabled(feedbackEmailURL() == nil)
            } footer: {
                Text(L10n.settingsDisclaimerMedical)
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .listRowSeparatorTint(Color(uiColor: .separator).opacity(0.5))
        .environment(\.defaultMinListRowHeight, 38)
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
        .onReceive(NotificationCenter.default.publisher(for: .settingsDidChangeOutsideSettings)) { _ in
            Task {
                await vm.loadSettings()
            }
        }
        .onChange(of: vm.bedtimeSlotEnabled) { _, _ in
            vm.scheduleAutoSave()
        }
        .onChange(of: vm.enableDailyCycleMode) { _, _ in
            vm.scheduleAutoSave()
        }
        .onChange(of: vm.autoSaveSignature) { _, _ in
            vm.scheduleAutoSave()
        }
        .onChange(of: isDailyCycleTargetDialogPresented) { _, isPresented in
            guard !isPresented else { return }
            dailyCycleDialogTargets = []
            dailyCycleDialogDate = nil
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
                analyticsRepository: container.analyticsRepository,
                schedulesUpdater: container.updateSchedulesUseCase
            )
            self.viewModel = vm
            await vm.loadSettings()
        }
    }

    private func label(for unit: GlucoseUnit) -> String {
        switch unit { case .mmolL: return L10n.unitMmolL; case .mgdL: return L10n.unitMgDL }
    }

    private func clampedMinutesSinceMidnight(_ value: Int) -> Int {
        min(max(value, 0), (23 * 60) + 59)
    }

    private func mealTimeBinding(hour: Binding<Int>, minute: Binding<Int>) -> Binding<Int> {
        Binding<Int>(
            get: {
                clampedMinutesSinceMidnight((hour.wrappedValue * 60) + minute.wrappedValue)
            },
            set: { newValue in
                let clamped = clampedMinutesSinceMidnight(newValue)
                hour.wrappedValue = clamped / 60
                minute.wrappedValue = clamped % 60
            }
        )
    }

    private func glucoseThresholdBinding(mmolBinding: Binding<Double>, vm: SettingsViewModel) -> Binding<Double> {
        Binding<Double>(
            get: {
                vm.displayGlucoseThreshold(mmolBinding.wrappedValue)
            },
            set: { newValue in
                let range = vm.glucoseThresholdRangeForCurrentUnit()
                let clamped = min(
                    max(newValue, range.lowerBound),
                    range.upperBound
                )
                mmolBinding.wrappedValue = vm.storedGlucoseThreshold(clamped)
            }
        )
    }

    private func dateTimeString(_ date: Date) -> String {
        return UIFormatters.dateMediumShortTime.string(from: date)
    }

    private func exportDateString(_ date: Date) -> String {
        UIFormatters.dateMedium.string(from: date)
    }

    @ViewBuilder
    private func exportDateButton(date: Date, sheet: ExportDatePickerSheet) -> some View {
        Button {
            exportDatePickerSheet = sheet
        } label: {
            HStack(spacing: DS.Spacing.xSmall) {
                Text(exportDateString(date))
                    .foregroundStyle(.secondary)
                Image(systemName: "calendar")
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func exportDatePickerSheetContent(for sheet: ExportDatePickerSheet) -> some View {
        NavigationStack {
            VStack(spacing: DS.Spacing.medium) {
                DatePicker(
                    "",
                    selection: exportDateBinding(for: sheet),
                    in: exportDateRange(for: sheet),
                    displayedComponents: [.date]
                )
                .datePickerStyle(.graphical)
                .labelsHidden()
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.Spacing.medium)
            .padding(.top, DS.Spacing.medium)
            .navigationTitle(sheet.title)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.quickEntryActionDone) {
                        exportDatePickerSheet = nil
                    }
                }
            }
        }
    }

    private func exportDateBinding(for sheet: ExportDatePickerSheet) -> Binding<Date> {
        switch sheet {
        case .from:
            return $exportStartDate
        case .to:
            return $exportEndDate
        }
    }

    private func exportDateRange(for sheet: ExportDatePickerSheet) -> ClosedRange<Date> {
        switch sheet {
        case .from:
            return Date.distantPast...exportEndDate
        case .to:
            return exportStartDate...Date.distantFuture
        }
    }

    private func feedbackEmailURL() -> URL? {
        guard
            let rawEmail = Bundle.main.object(forInfoDictionaryKey: "SUPPORT_EMAIL") as? String
        else {
            return nil
        }
        let email = rawEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty, !email.contains("$(") else { return nil }
        let subject = L10n.settingsFeedbackEmailSubject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "mailto:\(email)?subject=\(subject)")
    }
}

// MARK: - Settings Section Helpers

private struct SettingsSectionCard<Content: View, Footer: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footer: () -> Footer

    init(
        title: String,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder footer: @escaping () -> Footer
    ) {
        self.title = title
        self.content = content
        self.footer = footer
    }

    init(
        title: String,
        @ViewBuilder content: @escaping () -> Content
    ) where Footer == EmptyView {
        self.init(title: title, content: content, footer: { EmptyView() })
    }

    var body: some View {
        Section {
            content()
        } header: {
            Text(title)
                .textCase(nil)
        } footer: {
            footer()
        }
        .listRowBackground(Color(uiColor: .secondarySystemGroupedBackground).opacity(0.9))
    }
}

private struct ThresholdGroupHeader: View {
    let title: String
    var topPadding: CGFloat = 0

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.top, topPadding)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 2, trailing: 16))
    }
}

private struct SettingsRow<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        LabeledContent {
            trailing()
        } label: {
            Text(title)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(minHeight: 38)
        .settingsCompactRow()
    }
}

private struct SettingsToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    var toggleAccessibilityId: String? = nil

    var body: some View {
        let toggle = Toggle(isOn: $isOn) {
            Text(title)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(minHeight: 38)
        .settingsCompactRow()

        if let id = toggleAccessibilityId {
            toggle.accessibilityIdentifier(id)
        } else {
            toggle
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
            .frame(minHeight: 38)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .settingsCompactRow()
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
        .frame(height: 38)
        .background(Color(uiColor: .secondarySystemFill))
        .clipShape(Capsule())
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct DoubleValueCapsuleEditor: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 0.1
    var fractionDigits: Int = 1

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

            Text(
                value,
                format: .number.precision(.fractionLength(fractionDigits))
            )
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
        .frame(height: 38)
        .background(Color(uiColor: .secondarySystemFill))
        .clipShape(Capsule())
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct ExportShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

private enum ExportDatePickerSheet: String, Identifiable {
    case from
    case to

    var id: String { rawValue }

    var title: String {
        switch self {
        case .from:
            return L10n.settingsRowFrom
        case .to:
            return L10n.settingsRowTo
        }
    }
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct TimeOfDayPicker: View {
    @Binding var minutesSinceMidnight: Int

    private var selection: Binding<Date> {
        Binding<Date>(
            get: { date(from: minutesSinceMidnight) },
            set: { minutesSinceMidnight = minutes(from: $0) }
        )
    }

    var body: some View {
        DatePicker("", selection: selection, displayedComponents: [.hourAndMinute])
            .labelsHidden()
            .datePickerStyle(.compact)
            .frame(height: 34)
    }

    private func date(from minutes: Int) -> Date {
        let clamped = min(max(minutes, 0), (23 * 60) + 59)
        let calendar = Calendar.autoupdatingCurrent
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = clamped / 60
        components.minute = clamped % 60
        components.second = 0
        return calendar.date(from: components) ?? Date()
    }

    private func minutes(from date: Date) -> Int {
        let components = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute], from: date)
        let hour = min(max(components.hour ?? 0, 0), 23)
        let minute = min(max(components.minute ?? 0, 0), 59)
        return hour * 60 + minute
    }
}

private struct SettingsCompactRowModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }
}

private extension View {
    func settingsCompactRow() -> some View {
        modifier(SettingsCompactRowModifier())
    }
}

// MARK: - Weekday Grid Helper

private struct WeekdayGrid: View {
    @Binding var selected: Set<Int>

    private let calendar = Calendar.autoupdatingCurrent

    private var weekdayItems: [(value: Int, label: String)] {
        let firstWeekday = min(max(calendar.firstWeekday, 1), 7)
        let orderedValues = (0..<7).map { ((firstWeekday - 1 + $0) % 7) + 1 }
        return orderedValues.map { (value: $0, label: weekdayLabel(for: $0)) }
    }

    var body: some View {
        LazyVGrid(columns: Array(repeating: .init(.flexible(), spacing: 8), count: 7), spacing: 8) {
            ForEach(weekdayItems, id: \.value) { item in
                let isOn = selected.contains(item.value)
                Button(action: { toggle(item.value) }) {
                    Text(item.label)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(isOn ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func toggle(_ weekday: Int) {
        if selected.contains(weekday) { selected.remove(weekday) } else { selected.insert(weekday) }
    }

    private func weekdayLabel(for weekday: Int) -> String {
        guard (1...7).contains(weekday) else { return "" }
        let start = calendar.startOfDay(for: Date())
        guard let date = calendar.nextDate(
            after: start.addingTimeInterval(-1),
            matching: DateComponents(weekday: weekday),
            matchingPolicy: .nextTime,
            direction: .forward
        ) else {
            return ""
        }
        let symbol = calendar.shortWeekdaySymbols[(weekday - 1) % 7]
        let normalized = symbol.replacingOccurrences(of: ".", with: "").trimmingCharacters(in: .whitespaces)
        let fromDate = DateFormatter.weekdayChipFormatter.string(from: date)
        let compact = fromDate.replacingOccurrences(of: ".", with: "").trimmingCharacters(in: .whitespaces)
        let resolved = compact.isEmpty ? normalized : compact
        return resolved.count > 2 ? String(resolved.prefix(2)) : resolved
    }
}

private extension DateFormatter {
    static let weekdayChipFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .autoupdatingCurrent
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter
    }()
}

#Preview {
    NavigationStack { SettingsView() }
        .appContainer(.preview)
}
