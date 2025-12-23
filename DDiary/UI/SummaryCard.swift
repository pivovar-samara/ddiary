import SwiftUI

struct SummaryCard: View {
    let vm: HistoryViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.small) {
            Text("Summary")
                .font(.headline)

            if vm.selectedFilter == .both || vm.selectedFilter == .bp {
                VStack(alignment: .leading, spacing: DS.Spacing.xSmall) {
                    Text("Blood Pressure")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Grid(alignment: .leading, horizontalSpacing: DS.Spacing.small, verticalSpacing: DS.Spacing.xSmall) {
                        GridRow {
                            Text("Count").foregroundStyle(.secondary)
                            Text(formatInt(vm.bpCount))
                                .monospacedDigit()
                                .gridColumnAlignment(.trailing)
                        }
                        GridRow {
                            Text("SYS min/max/avg").foregroundStyle(.secondary)
                            Text("\(formatInt(vm.bpSystolicMin))/\(formatInt(vm.bpSystolicMax))/\(format1(vm.bpSystolicAvg))")
                                .monospacedDigit()
                                .gridColumnAlignment(.trailing)
                        }
                        GridRow {
                            Text("DIA min/max/avg").foregroundStyle(.secondary)
                            Text("\(formatInt(vm.bpDiastolicMin))/\(formatInt(vm.bpDiastolicMax))/\(format1(vm.bpDiastolicAvg))")
                                .monospacedDigit()
                                .gridColumnAlignment(.trailing)
                        }
                        GridRow {
                            Text("Pulse min/max/avg").foregroundStyle(.secondary)
                            Text("\(formatInt(vm.pulseMin))/\(formatInt(vm.pulseMax))/\(format1(vm.pulseAvg))")
                                .monospacedDigit()
                                .gridColumnAlignment(.trailing)
                        }
                    }
                }
            }

            if vm.selectedFilter == .both || vm.selectedFilter == .glucose {
                VStack(alignment: .leading, spacing: DS.Spacing.xSmall) {
                    Text("Glucose")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Grid(alignment: .leading, horizontalSpacing: DS.Spacing.small, verticalSpacing: DS.Spacing.xSmall) {
                        GridRow {
                            Text("Count").foregroundStyle(.secondary)
                            Text(formatInt(vm.glucoseCount))
                                .monospacedDigit()
                                .gridColumnAlignment(.trailing)
                        }
                        GridRow {
                            Text("Min/Max/Avg").foregroundStyle(.secondary)
                            Text(glucoseStatsString())
                                .monospacedDigit()
                                .lineLimit(2)
                                .minimumScaleFactor(0.85)
                                .multilineTextAlignment(.trailing)
                                .fixedSize(horizontal: false, vertical: true)
                                .gridColumnAlignment(.trailing)
                        }
                    }
                }
            }
        }
        .cardContainer()
    }

    private func glucoseStatsString() -> String {
        // Determine display unit from first measurement; default to mmol/L
        let unit: GlucoseUnit = vm.glucoseMeasurements.first?.unit ?? .mmolL
        let minStr: String = vm.glucoseMin.flatMap { UIFormatters.formatGlucoseValue($0, unit: unit) } ?? "—"
        let maxStr: String = vm.glucoseMax.flatMap { UIFormatters.formatGlucoseValue($0, unit: unit) } ?? "—"
        let avgStr: String = vm.glucoseAvg.flatMap { UIFormatters.formatGlucoseValue($0, unit: unit) } ?? "—"
        return "\(minStr)/\(maxStr)/\(avgStr) \(displayUnit(unit))"
    }

    // MARK: - Helpers
    private var glucoseUnitString: String {
        if let unit = vm.glucoseMeasurements.first?.unit {
            return displayUnit(unit)
        } else {
            return displayUnit(.mmolL)
        }
    }

    private func displayUnit(_ unit: GlucoseUnit) -> String {
        switch unit {
        case .mmolL: return "mmol/L"
        case .mgdL: return "mg/dL"
        }
    }

    private func formatInt(_ value: Int?) -> String {
        guard let value else { return "—" }
        return UIFormatters.numberInt.string(from: NSNumber(value: value)) ?? String(value)
    }

    private func formatInt(_ value: Int) -> String {
        UIFormatters.numberInt.string(from: NSNumber(value: value)) ?? String(value)
    }

    private func format1(_ value: Double?) -> String {
        guard let v = value, v.isFinite else { return "—" }
        return UIFormatters.numberOneDecimal.string(from: NSNumber(value: v)) ?? String(format: "%.1f", v)
    }

    private func format2(_ value: Double?) -> String {
        guard let v = value, v.isFinite else { return "—" }
        return UIFormatters.numberTwoDecimals.string(from: NSNumber(value: v)) ?? String(format: "%.2f", v)
    }
}
