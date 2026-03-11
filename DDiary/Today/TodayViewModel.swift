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
    public let matchedMeasurementId: UUID?

    public init(
        id: UUID = UUID(),
        displayTime: String,
        scheduledDate: Date,
        status: SlotStatus,
        matchedMeasurementId: UUID?
    ) {
        self.id = id
        self.displayTime = displayTime
        self.scheduledDate = scheduledDate
        self.status = status
        self.matchedMeasurementId = matchedMeasurementId
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
    public let matchedMeasurementId: UUID?

    public init(
        id: UUID = UUID(),
        mealSlot: MealSlot,
        measurementType: GlucoseMeasurementType,
        displayTime: String,
        scheduledDate: Date,
        status: SlotStatus,
        matchedMeasurementId: UUID?
    ) {
        self.id = id
        self.mealSlot = mealSlot
        self.measurementType = measurementType
        self.displayTime = displayTime
        self.scheduledDate = scheduledDate
        self.status = status
        self.matchedMeasurementId = matchedMeasurementId
    }
}

// MARK: - TodayViewModel

@MainActor
@Observable
public final class TodayViewModel {
    public enum RefreshReason: Sendable {
        case initialLoad
        case appBecameActive
        case screenBecameVisible
        case settingsSaved
        case quickEntryDismissed
        case manual
    }

    // Dependencies
    private let getTodayOverviewUseCase: GetTodayOverviewUseCase
    private let logBPMeasurementUseCase: LogBPMeasurementUseCase
    private let logGlucoseMeasurementUseCase: LogGlucoseMeasurementUseCase
    private let rescheduleGlucoseCycleUseCase: RescheduleGlucoseCycleUseCase
    private let schedulesUpdater: any SchedulesUpdating
    private let notificationsRepository: any NotificationsRepository

    // State
    public private(set) var isLoading: Bool = false
    public private(set) var isShiftingCycleDay: Bool = false
    public private(set) var isSwitchingCycleTarget: Bool = false
    public private(set) var isDailyCycleModeEnabled: Bool = false
    public private(set) var availableCycleSwitchTargets: [MealSlot] = []
    public private(set) var errorMessage: String? = nil
    private var isRefreshInProgress: Bool = false
    private var hasPendingRefresh: Bool = false

    public private(set) var bpSlots: [BPSlotViewModel] = []
    public private(set) var glucoseSlots: [GlucoseSlotViewModel] = []
    public var selectedGlucoseSlot: GlucoseSlotViewModel? = nil

    // Optional references to existing measurements for quick editing
    public var selectedExistingBP: BPMeasurement? = nil
    public var selectedExistingGlucose: GlucoseMeasurement? = nil

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
            title: L10n.settingsRowBloodPressure,
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
        logGlucoseMeasurementUseCase: LogGlucoseMeasurementUseCase,
        rescheduleGlucoseCycleUseCase: RescheduleGlucoseCycleUseCase,
        schedulesUpdater: any SchedulesUpdating,
        notificationsRepository: any NotificationsRepository
    ) {
        self.getTodayOverviewUseCase = getTodayOverviewUseCase
        self.logBPMeasurementUseCase = logBPMeasurementUseCase
        self.logGlucoseMeasurementUseCase = logGlucoseMeasurementUseCase
        self.rescheduleGlucoseCycleUseCase = rescheduleGlucoseCycleUseCase
        self.schedulesUpdater = schedulesUpdater
        self.notificationsRepository = notificationsRepository
    }

    // MARK: - Intents

    public func refresh() async {
        await refreshIfNeeded(reason: .manual)
    }

    public func refreshIfNeeded(reason _: RefreshReason) async {
        if isRefreshInProgress {
            hasPendingRefresh = true
            return
        }

        repeat {
            hasPendingRefresh = false
            await performRefresh()
        } while hasPendingRefresh
    }

    private func performRefresh() async {
        isRefreshInProgress = true
        defer { isRefreshInProgress = false }

        errorMessage = nil
        isLoading = true
        
        let overview = await getTodayOverviewUseCase.compute()
        isDailyCycleModeEnabled = overview.isDailyCycleModeEnabled
        let now = Date()

        // BP slots
        bpSlots = overview.bpSlots.map { slot in
            let status = Self.computeStatus(now: now, scheduled: slot.date, completed: slot.completed)
            return BPSlotViewModel(
                displayTime: UIFormatters.formatTime(slot.date),
                scheduledDate: slot.date,
                status: status,
                matchedMeasurementId: slot.matchedMeasurementId
            )
        }

        // Glucose slots
        glucoseSlots = overview.glucoseSlots.map { slot in
            let status = Self.computeStatus(now: now, scheduled: slot.date, completed: slot.completed)
            return GlucoseSlotViewModel(
                mealSlot: slot.mealSlot,
                measurementType: slot.measurementType,
                displayTime: UIFormatters.formatTime(slot.date),
                scheduledDate: slot.date,
                status: status,
                matchedMeasurementId: slot.matchedMeasurementId
            )
        }

        if isDailyCycleModeEnabled {
            availableCycleSwitchTargets = await rescheduleGlucoseCycleUseCase.availableForwardTargetsForToday(today: now)
        } else {
            availableCycleSwitchTargets = []
        }

        await syncNotificationsFromTodayOverview(overview)

        isLoading = false
    }

    public func shiftCycleDayForward() async {
        guard isDailyCycleModeEnabled else { return }
        guard !isShiftingCycleDay else { return }

        errorMessage = nil
        isShiftingCycleDay = true
        defer { isShiftingCycleDay = false }

        let shifted = await rescheduleGlucoseCycleUseCase.shiftTodayForward()
        guard shifted else { return }

        do {
            try await schedulesUpdater.scheduleFromCurrentSettings()
        } catch {
            errorMessage = L10n.settingsErrorSavedButRemindersNotUpdated
        }
        NotificationCenter.default.post(name: .settingsDidChangeOutsideSettings, object: nil)
        await refresh()
    }

    public func cycleSwitchTargets(for slot: GlucoseSlotViewModel) -> [MealSlot] {
        guard isDailyCycleModeEnabled else { return [] }
        guard slot.measurementType == .beforeMeal || slot.measurementType == .bedtime else { return [] }
        guard slot.status != .completed else { return [] }
        return availableCycleSwitchTargets
    }

    public func cycleSlotTitle(_ slot: MealSlot) -> String {
        switch slot {
        case .breakfast:
            return L10n.settingsRowBreakfast
        case .lunch:
            return L10n.settingsRowLunch
        case .dinner:
            return L10n.settingsRowDinner
        case .none:
            return L10n.settingsRowBedtime
        }
    }

    public func switchDailyCycleTarget(to mealSlot: MealSlot, today: Date = Date()) async {
        guard !isSwitchingCycleTarget else { return }
        guard availableCycleSwitchTargets.contains(mealSlot) else { return }

        errorMessage = nil
        isSwitchingCycleTarget = true
        defer { isSwitchingCycleTarget = false }

        let shifted = await rescheduleGlucoseCycleUseCase.setTodayTarget(mealSlot, today: today)
        guard shifted else { return }

        do {
            try await schedulesUpdater.scheduleFromCurrentSettings()
        } catch {
            errorMessage = L10n.settingsErrorSavedButRemindersNotUpdated
        }
        NotificationCenter.default.post(name: .settingsDidChangeOutsideSettings, object: nil)
        await refresh()
    }

    public func onBPSlotTapped(_ slot: BPSlotViewModel) {
        // For now, just present a stub quick entry sheet.
        presentBPQuickEntry = true
        // Later: prefill with scheduledDate, and on save call logBPMeasurementUseCase
        // No change here yet; existing measurement reference will be handled elsewhere
    }

    public func onGlucoseSlotTapped(_ slot: GlucoseSlotViewModel) {
        selectedGlucoseSlot = slot
        presentGlucoseQuickEntry = true
        // Later: prefill with slot.mealSlot & slot.measurementType, call logGlucoseMeasurementUseCase
        // Existing measurement reference will be handled in the view layer
    }

    @discardableResult
    func presentQuickEntryFromNotification(
        target: NotificationQuickEntryTarget,
        scheduledDate: Date? = nil
    ) -> Date? {
        switch target {
        case .bloodPressure:
            selectedGlucoseSlot = nil
            presentGlucoseQuickEntry = false
            presentBPQuickEntry = true
            return scheduledDate ?? matchingBPSlot()?.scheduledDate
        case .glucose(let mealSlot, let measurementType):
            presentBPQuickEntry = false
            selectedGlucoseSlot = matchingGlucoseSlot(
                mealSlot: mealSlot,
                measurementType: measurementType
            ) ?? GlucoseSlotViewModel(
                mealSlot: mealSlot,
                measurementType: measurementType,
                displayTime: "",
                scheduledDate: Date(),
                status: .due,
                matchedMeasurementId: nil
            )
            presentGlucoseQuickEntry = true
            return scheduledDate ?? selectedGlucoseSlot?.scheduledDate
        }
    }

    // MARK: - Helpers

    private func matchingGlucoseSlot(
        mealSlot: MealSlot,
        measurementType: GlucoseMeasurementType
    ) -> GlucoseSlotViewModel? {
        let now = Date()
        return glucoseSlots
            .filter { $0.mealSlot == mealSlot && $0.measurementType == measurementType }
            .min { left, right in
                abs(left.scheduledDate.timeIntervalSince(now)) < abs(right.scheduledDate.timeIntervalSince(now))
            }
    }

    private func matchingBPSlot(referenceDate: Date = Date()) -> BPSlotViewModel? {
        bpSlots
            .filter { $0.status != .completed }
            .min { left, right in
                abs(left.scheduledDate.timeIntervalSince(referenceDate)) < abs(right.scheduledDate.timeIntervalSince(referenceDate))
            }
    }

    private static func computeStatus(now: Date, scheduled: Date, completed: Bool) -> SlotStatus {
        if completed { return .completed }
        if now < scheduled { return .scheduled }
        if now <= scheduled.addingTimeInterval(2 * 60 * 60) { return .due }
        return .missed
    }

    private func syncNotificationsFromTodayOverview(_ overview: TodayOverview) async {
        var processedBPDates: Set<Date> = []
        for slot in overview.bpSlots where slot.completed {
            guard processedBPDates.insert(slot.date).inserted else { continue }
            await notificationsRepository.cancelPlannedBloodPressureNotification(at: slot.date)
        }

        var processedGlucoseSlots: Set<String> = []
        for slot in overview.glucoseSlots where slot.completed {
            let key = "\(slot.measurementType.rawValue)|\(Int(slot.date.timeIntervalSince1970))"
            guard processedGlucoseSlots.insert(key).inserted else { continue }
            await notificationsRepository.cancelPlannedGlucoseNotification(
                measurementType: slot.measurementType,
                at: slot.date
            )
        }
    }
}
