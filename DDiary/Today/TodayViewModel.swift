import Foundation
import Observation

// MARK: - Slot Status

public enum SlotStatus: String, Sendable {
    case scheduled
    case due
    case missed
    case completed
}

// MARK: - BP Slot VM

public struct BPSlotViewModel: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let displayTime: String
    public let scheduledDate: Date
    public let status: SlotStatus

    public init(id: UUID = UUID(), displayTime: String, scheduledDate: Date, status: SlotStatus) {
        self.id = id
        self.displayTime = displayTime
        self.scheduledDate = scheduledDate
        self.status = status
    }
}

// MARK: - Glucose Slot VM

public struct GlucoseSlotViewModel: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let mealSlot: MealSlot
    public let measurementType: GlucoseMeasurementType
    public let displayTime: String
    public let scheduledDate: Date
    public let status: SlotStatus

    public init(
        id: UUID = UUID(),
        mealSlot: MealSlot,
        measurementType: GlucoseMeasurementType,
        displayTime: String,
        scheduledDate: Date,
        status: SlotStatus
    ) {
        self.id = id
        self.mealSlot = mealSlot
        self.measurementType = measurementType
        self.displayTime = displayTime
        self.scheduledDate = scheduledDate
        self.status = status
    }
}

// MARK: - TodayViewModel

@MainActor
@Observable
public final class TodayViewModel {
    // Dependencies
    private let getTodayOverviewUseCase: GetTodayOverviewUseCase
    private let logBPMeasurementUseCase: LogBPMeasurementUseCase
    private let logGlucoseMeasurementUseCase: LogGlucoseMeasurementUseCase

    // State
    public private(set) var isLoading: Bool = false
    public private(set) var errorMessage: String? = nil

    public private(set) var bpSlots: [BPSlotViewModel] = []
    public private(set) var glucoseSlots: [GlucoseSlotViewModel] = []
    public var selectedGlucoseSlot: GlucoseSlotViewModel? = nil

    // Quick entry presentation flags (stubs for now)
    public var presentBPQuickEntry: Bool = false
    public var presentGlucoseQuickEntry: Bool = false

    // MARK: - UI Grouping (computed)

    public var bpDue: [BPSlotViewModel] {
        bpSlots
            .filter { $0.status == .due }
            .sorted { $0.scheduledDate < $1.scheduledDate }
    }

    public var bpScheduled: [BPSlotViewModel] {
        bpSlots
            .filter { $0.status == .scheduled }
            .sorted { $0.scheduledDate < $1.scheduledDate }
    }

    public var bpMissed: [BPSlotViewModel] {
        bpSlots
            .filter { $0.status == .missed }
            .sorted { $0.scheduledDate < $1.scheduledDate }
    }

    public var bpCompleted: [BPSlotViewModel] {
        bpSlots
            .filter { $0.status == .completed }
            .sorted { $0.scheduledDate < $1.scheduledDate }
    }

    public var glucoseDue: [GlucoseSlotViewModel] {
        glucoseSlots
            .filter { $0.status == .due }
            .sorted { $0.scheduledDate < $1.scheduledDate }
    }

    public var glucoseScheduled: [GlucoseSlotViewModel] {
        glucoseSlots
            .filter { $0.status == .scheduled }
            .sorted { $0.scheduledDate < $1.scheduledDate }
    }

    public var glucoseMissed: [GlucoseSlotViewModel] {
        glucoseSlots
            .filter { $0.status == .missed }
            .sorted { $0.scheduledDate < $1.scheduledDate }
    }

    public var glucoseCompleted: [GlucoseSlotViewModel] {
        glucoseSlots
            .filter { $0.status == .completed }
            .sorted { $0.scheduledDate < $1.scheduledDate }
    }

    // MARK: - Unified Items (UI-only)

    public enum TodayItemKind: String, Sendable { case bp, glucose }

    public struct TodayItem: Identifiable, Sendable, Equatable {
        public enum Payload: Sendable, Equatable {
            case bp(BPSlotViewModel)
            case glucose(GlucoseSlotViewModel)
        }
        public let id: UUID
        public let kind: TodayItemKind
        public let title: String
        public let timeText: String
        public let scheduledDate: Date
        public let status: SlotStatus
        public let payload: Payload
    }

    public var itemsDue: [TodayItem] {
        let bp = bpDue.map(mapBP)
        let gl = glucoseDue.map(mapGlucose)
        return (bp + gl).sorted { $0.scheduledDate < $1.scheduledDate }
    }

    public var itemsScheduled: [TodayItem] {
        let bp = bpScheduled.map(mapBP)
        let gl = glucoseScheduled.map(mapGlucose)
        return (bp + gl).sorted { $0.scheduledDate < $1.scheduledDate }
    }

    public var itemsMissed: [TodayItem] {
        let bp = bpMissed.map(mapBP)
        let gl = glucoseMissed.map(mapGlucose)
        return (bp + gl).sorted { $0.scheduledDate < $1.scheduledDate }
    }

    public var itemsCompleted: [TodayItem] {
        let bp = bpCompleted.map(mapBP)
        let gl = glucoseCompleted.map(mapGlucose)
        return (bp + gl).sorted { $0.scheduledDate < $1.scheduledDate }
    }

    private func mapBP(_ slot: BPSlotViewModel) -> TodayItem {
        TodayItem(
            id: slot.id,
            kind: .bp,
            title: String(localized: "Blood Pressure", comment: "BP row title"),
            timeText: slot.displayTime,
            scheduledDate: slot.scheduledDate,
            status: slot.status,
            payload: .bp(slot)
        )
    }

    private func mapGlucose(_ slot: GlucoseSlotViewModel) -> TodayItem {
        TodayItem(
            id: slot.id,
            kind: .glucose,
            title: UIStrings.glucoseTitle(mealSlot: slot.mealSlot.rawValue, measurementType: slot.measurementType.rawValue),
            timeText: slot.displayTime,
            scheduledDate: slot.scheduledDate,
            status: slot.status,
            payload: .glucose(slot)
        )
    }

    public init(
        getTodayOverviewUseCase: GetTodayOverviewUseCase,
        logBPMeasurementUseCase: LogBPMeasurementUseCase,
        logGlucoseMeasurementUseCase: LogGlucoseMeasurementUseCase
    ) {
        self.getTodayOverviewUseCase = getTodayOverviewUseCase
        self.logBPMeasurementUseCase = logBPMeasurementUseCase
        self.logGlucoseMeasurementUseCase = logGlucoseMeasurementUseCase
    }

    // MARK: - Intents

    public func refresh() async {
        isLoading = true
        
        let overview = await getTodayOverviewUseCase.compute()
        let now = Date()
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short

        // BP slots
        bpSlots = overview.bpTimes.map { date in
            let status = Self.computeStatus(now: now, scheduled: date, completed: false)
            return BPSlotViewModel(
                displayTime: timeFormatter.string(from: date),
                scheduledDate: date,
                status: status
            )
        }

        // Glucose slots
        glucoseSlots = overview.glucoseSlots.map { slot in
            let status = Self.computeStatus(now: now, scheduled: slot.date, completed: false)
            return GlucoseSlotViewModel(
                mealSlot: slot.mealSlot,
                measurementType: slot.measurementType,
                displayTime: timeFormatter.string(from: slot.date),
                scheduledDate: slot.date,
                status: status
            )
        }

        isLoading = false
    }

    public func onBPSlotTapped(_ slot: BPSlotViewModel) {
        // For now, just present a stub quick entry sheet.
        presentBPQuickEntry = true
        // Later: prefill with scheduledDate, and on save call logBPMeasurementUseCase
    }

    public func onGlucoseSlotTapped(_ slot: GlucoseSlotViewModel) {
        selectedGlucoseSlot = slot
        presentGlucoseQuickEntry = true
        // Later: prefill with slot.mealSlot & slot.measurementType, call logGlucoseMeasurementUseCase
    }

    // MARK: - Helpers

    private static func computeStatus(now: Date, scheduled: Date, completed: Bool) -> SlotStatus {
        if completed { return .completed }
        if now < scheduled { return .scheduled }
        if now <= scheduled.addingTimeInterval(2 * 60 * 60) { return .due }
        return .missed
    }
}

