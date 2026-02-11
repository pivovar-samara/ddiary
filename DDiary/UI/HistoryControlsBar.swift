import SwiftUI

struct HistoryControlsBar: View {
    @Binding var selectedFilter: HistoryViewModel.Filter
    var selectedDateRange: HistoryViewModel.DateRange
    var onFilterChange: (HistoryViewModel.Filter) -> Void
    var onRangeChange: (HistoryViewModel.DateRange) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.small) {
            Picker(L10n.historyFilterLabel, selection: $selectedFilter) {
                ForEach(HistoryViewModel.Filter.allCases) { f in
                    Text(f.title).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedFilter) { _, newValue in
                onFilterChange(newValue)
            }

            HStack(spacing: DS.Spacing.xSmall) {
                chip(title: L10n.historyRangeToday, preset: .today)
                chip(title: L10n.historyRange7Days, preset: .days7)
                chip(title: L10n.historyRange30Days, preset: .days30)
                Spacer(minLength: 0)
            }
        }
    }

    private func chip(title: String, preset: HistoryViewModel.RangePreset) -> some View {
        let isSelected = isPresetSelected(preset)
        return Button(title) {
            onRangeChange(HistoryViewModel.defaultRange(preset))
        }
        .buttonStyle(DateRangeChipStyle(isSelected: isSelected))
        .accessibilityLabel(L10n.historyRangeAccessibilityLabel(title))
    }

    private func isPresetSelected(_ preset: HistoryViewModel.RangePreset) -> Bool {
        let cal = Calendar.current
        let now = Date()
        let startToday = cal.startOfDay(for: now)
        switch preset {
        case .today:
            let endToday = cal.date(byAdding: DateComponents(day: 1, second: -1), to: startToday) ?? now
            return selectedDateRange.startDate == startToday && selectedDateRange.endDate == endToday
        case .days7:
            let start = cal.date(byAdding: .day, value: -6, to: startToday) ?? now
            let nearNow = abs(selectedDateRange.endDate.timeIntervalSince(now)) < 12 * 3600
            return abs(selectedDateRange.startDate.timeIntervalSince(start)) < 1 && nearNow
        case .days30:
            let start = cal.date(byAdding: .day, value: -29, to: startToday) ?? now
            let nearNow = abs(selectedDateRange.endDate.timeIntervalSince(now)) < 12 * 3600
            return abs(selectedDateRange.startDate.timeIntervalSince(start)) < 1 && nearNow
        }
    }
}

struct DateRangeChipStyle: ButtonStyle {
    var isSelected: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline)
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color(.tertiarySystemFill) : Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? Color.secondary.opacity(0.5) : Color.clear, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}
