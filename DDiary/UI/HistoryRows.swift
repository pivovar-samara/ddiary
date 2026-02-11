import SwiftUI

@MainActor
struct BPHistoryRow: View {
    let measurement: BPMeasurement
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.small) {
                TypeBadgeView(text: "BP", width: 44)

                VStack(alignment: .leading, spacing: DS.Spacing.xSmall) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(measurement.systolic)/\(measurement.diastolic)")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                        Text(L10n.historyRowPulse(String(measurement.pulse)))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    if let c = measurement.comment, !c.isEmpty {
                        Text(c)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    if showOutlierWarning {
                        ValueWarningCallout()
                    }
                }

                Spacer()

                Text(UIFormatters.formatTime(measurement.timestamp))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardContainer(padding: DS.Spacing.small)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("history.row.bp.\(measurement.id.uuidString)")
    }

    private var showOutlierWarning: Bool {
        isOutlier(systolic: measurement.systolic, diastolic: measurement.diastolic, pulse: measurement.pulse)
    }

    private func isOutlier(systolic: Int, diastolic: Int, pulse: Int) -> Bool {
        // Broad sanity band to catch obvious entry mistakes without medical claims
        if systolic <= 0 || diastolic <= 0 || pulse <= 0 { return true }
        if diastolic > systolic { return true }
        if systolic < 60 || systolic > 260 { return true }
        if diastolic < 30 || diastolic > 180 { return true }
        if pulse < 30 || pulse > 220 { return true }
        return false
    }
}

@MainActor
struct GlucoseHistoryRow: View {
    let measurement: GlucoseMeasurement
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.small) {
                TypeBadgeView(text: "GLU", width: 44)

                VStack(alignment: .leading, spacing: DS.Spacing.xSmall) {
                    if isMissing {
                        Text(L10n.historyRowNotEntered)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(UIFormatters.formatGlucoseValue(measurement.value, unit: measurement.unit))
                                .font(.title3)
                                .fontWeight(.semibold)
                                .monospacedDigit()
                            Text(displayUnit(measurement.unit))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(UIStrings.glucoseTitle(mealSlot: measurement.mealSlot.rawValue, measurementType: measurement.measurementType.rawValue))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if let c = measurement.comment, !c.isEmpty {
                        Text(c)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    if showOutlierWarning {
                        ValueWarningCallout()
                    }
                }

                Spacer()

                Text(UIFormatters.formatTime(measurement.timestamp))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardContainer(padding: DS.Spacing.small)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("history.row.glucose.\(measurement.id.uuidString)")
    }

    private var isMissing: Bool {
        !measurement.value.isFinite || measurement.value <= 0
    }

    private var showOutlierWarning: Bool {
        guard !isMissing else { return false }
        return isOutlier(value: measurement.value, unit: measurement.unit)
    }

    private func isOutlier(value: Double, unit: GlucoseUnit) -> Bool {
        let mmol: Double = (unit == .mmolL) ? value : value / 18.0
        // Broad sanity band to catch obvious entry mistakes without medical claims
        return mmol < 2.0 || mmol > 33.0
    }

    private func displayUnit(_ unit: GlucoseUnit) -> String {
        switch unit {
        case .mmolL: return L10n.unitMmolL
        case .mgdL: return L10n.unitMgDL
        }
    }
}
private struct ValueWarningCallout: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(.orange)
            Text(L10n.historyRowCheckValue)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
