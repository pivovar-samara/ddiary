import Foundation
import Observation

@MainActor
@Observable
final class HistoryViewModel {
    // MARK: - Filter & Range
    enum Filter: String, CaseIterable, Identifiable, Hashable {
        case both
        case bp
        case glucose
        var id: String { rawValue }
        var title: String {
            switch self {
            case .both: return "Both"
            case .bp: return "BP"
            case .glucose: return "Glucose"
            }
        }
    }

    struct DateRange: Equatable {
        var startDate: Date
        var endDate: Date
    }

    // MARK: - Published State
    var selectedFilter: Filter = .both
    var selectedDateRange: DateRange

    var isLoading: Bool = false
    var errorMessage: String? = nil

    var bpMeasurements: [BPMeasurement] = []
    var glucoseMeasurements: [GlucoseMeasurement] = []

    // Aggregates
    var bpCount: Int = 0
    var bpSystolicMin: Int?
    var bpSystolicMax: Int?
    var bpSystolicAvg: Double?
    var bpDiastolicMin: Int?
    var bpDiastolicMax: Int?
    var bpDiastolicAvg: Double?
    var pulseMin: Int?
    var pulseMax: Int?
    var pulseAvg: Double?

    var glucoseCount: Int = 0
    var glucoseMin: Double?
    var glucoseMax: Double?
    var glucoseAvg: Double?

    // Change propagation
    private var pendingReload = false
    private var reloadDebounceTask: Task<Void, Never>?

    // MARK: - Dependencies
    private let getHistory: GetHistoryUseCase

    // MARK: - Init
    init(getHistory: GetHistoryUseCase, initialRange: DateRange = HistoryViewModel.defaultRange(.days7)) {
        self.getHistory = getHistory
        self.selectedDateRange = initialRange
    }

    // MARK: - Public API
    func loadHistory() async {
        isLoading = true
        errorMessage = nil
        do {
            let now = Date()
            let endNearNow = abs(selectedDateRange.endDate.timeIntervalSince(now)) < 12 * 3600
            let effectiveEnd = endNearNow ? now : selectedDateRange.endDate

            let includeBP = selectedFilter == .both || selectedFilter == .bp
            let includeGlucose = selectedFilter == .both || selectedFilter == .glucose
            let (bp, glucose) = try await getHistory.fetch(
                from: selectedDateRange.startDate,
                to: effectiveEnd,
                includeBP: includeBP,
                includeGlucose: includeGlucose
            )
            self.bpMeasurements = bp
            self.glucoseMeasurements = glucose
            computeAggregates()
            isLoading = false
        } catch {
            // For v1, expose a lightweight error message for UI; keep arrays empty.
            self.bpMeasurements = []
            self.glucoseMeasurements = []
            resetAggregates()
            errorMessage = (error as NSError).localizedDescription
            isLoading = false
        }
    }

    func updateFilter(_ filter: Filter) async {
        self.selectedFilter = filter
        await loadHistory()
    }

    func updateDateRange(_ range: DateRange) async {
        self.selectedDateRange = range
        await loadHistory()
    }

    // MARK: - Aggregates
    private func computeAggregates() {
        // BP
        bpCount = bpMeasurements.count
        if !bpMeasurements.isEmpty {
            bpSystolicMin = bpMeasurements.map { $0.systolic }.min()
            bpSystolicMax = bpMeasurements.map { $0.systolic }.max()
            bpSystolicAvg = average(bpMeasurements.map { Double($0.systolic) })

            bpDiastolicMin = bpMeasurements.map { $0.diastolic }.min()
            bpDiastolicMax = bpMeasurements.map { $0.diastolic }.max()
            bpDiastolicAvg = average(bpMeasurements.map { Double($0.diastolic) })

            pulseMin = bpMeasurements.map { $0.pulse }.min()
            pulseMax = bpMeasurements.map { $0.pulse }.max()
            pulseAvg = average(bpMeasurements.map { Double($0.pulse) })
        } else {
            bpSystolicMin = nil; bpSystolicMax = nil; bpSystolicAvg = nil
            bpDiastolicMin = nil; bpDiastolicMax = nil; bpDiastolicAvg = nil
            pulseMin = nil; pulseMax = nil; pulseAvg = nil
        }

        // Glucose
        glucoseCount = glucoseMeasurements.count
        if !glucoseMeasurements.isEmpty {
            let values: [Double] = glucoseMeasurements.map { $0.value }
            let validValues = values.filter { $0.isFinite && $0 >= 0 }
            if validValues.isEmpty {
                glucoseMin = nil; glucoseMax = nil; glucoseAvg = nil
            } else {
                glucoseMin = validValues.min()
                glucoseMax = validValues.max()
                let sum: Double = validValues.reduce(0.0, +)
                glucoseAvg = sum / Double(validValues.count)
            }
        } else {
            glucoseMin = nil; glucoseMax = nil; glucoseAvg = nil
        }
    }

    private func resetAggregates() {
        bpCount = 0
        bpSystolicMin = nil; bpSystolicMax = nil; bpSystolicAvg = nil
        bpDiastolicMin = nil; bpDiastolicMax = nil; bpDiastolicAvg = nil
        pulseMin = nil; pulseMax = nil; pulseAvg = nil
        glucoseCount = 0
        glucoseMin = nil; glucoseMax = nil; glucoseAvg = nil
    }

    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    func listenForChanges() async {
        for await _ in NotificationCenter.default.notifications(named: .measurementsDidChange) {
            scheduleReloadDebounced()
        }
    }
    
    private func scheduleReloadDebounced() {
        reloadDebounceTask?.cancel()
        reloadDebounceTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 200_000_000)
            await self.requestReload()
        }
    }
    
    private func requestReload() async {
        // Если уже грузим — пометим, что надо перезагрузить после
        if isLoading {
            pendingReload = true
            return
        }

        await loadHistory()

        // Если во время загрузки прилетели изменения — один догоняющий reload
        if pendingReload {
            pendingReload = false
            await loadHistory()
        }
    }
}

// MARK: - Presets
extension HistoryViewModel {
    enum RangePreset { case today, days7, days30 }

    static func defaultRange(_ preset: RangePreset) -> DateRange {
        let cal = Calendar.current
        let now = Date()
        switch preset {
        case .today:
            let start = cal.startOfDay(for: now)
            let end = cal.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? now
            return DateRange(startDate: start, endDate: end)
        case .days7:
            let end = now
            let start = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: now)) ?? now
            return DateRange(startDate: start, endDate: end)
        case .days30:
            let end = now
            let start = cal.date(byAdding: .day, value: -29, to: cal.startOfDay(for: now)) ?? now
            return DateRange(startDate: start, endDate: end)
        }
    }
}

