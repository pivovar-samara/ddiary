import Foundation
import Observation
import OSLog

extension Notification.Name {
    nonisolated static let settingsDidSave = Notification.Name("SettingsDidSave")
    nonisolated static let settingsDidChangeOutsideSettings = Notification.Name("SettingsDidChangeOutsideSettings")
}

@MainActor
@Observable
final class SettingsViewModel {
    private enum UserSurfacePolicy {
        case suppressed
        case showErrorDescription
        case showMessage(String)

        var loggingValue: String {
            switch self {
            case .suppressed:
                return "suppressed"
            case .showErrorDescription:
                return "error_description"
            case .showMessage:
                return "message"
            }
        }
    }

    // MARK: - Dependencies
    private let settingsRepository: any SettingsRepository
    private let googleIntegrationRepository: any GoogleIntegrationRepository
    private let exportCSVUseCase: ExportCSVUseCase
    private let measurementsRepository: any MeasurementsRepository
    private let googleSheetsClient: any GoogleSheetsClient
    private let analyticsRepository: any AnalyticsRepository
    private let schedulesUpdater: any SchedulesUpdating
    private let googleSignIn: @MainActor () async throws -> GoogleOAuthTokens
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "DDiary",
        category: "SettingsViewModel"
    )
    private let mgdLPerMmolL: Double = 18.0

    // MARK: - Backing models (MainActor-bound)
    private var settingsModel: UserSettings?
    private var googleIntegrationModel: GoogleIntegration?

    // MARK: - UI State
    var isLoading: Bool = false
    var errorMessage: String? = nil
    var isGoogleSyncInProgress: Bool = false
    var isGoogleOperationInProgress: Bool = false
    var isGoogleBusy: Bool { isGoogleSyncInProgress || isGoogleOperationInProgress }

    // MARK: - UserSettings mirrors
    var glucoseUnit: GlucoseUnit = .mmolL

    var breakfastHour: Int = 8
    var breakfastMinute: Int = 0
    var lunchHour: Int = 13
    var lunchMinute: Int = 0
    var dinnerHour: Int = 19
    var dinnerMinute: Int = 0
    var bedtimeSlotEnabled: Bool = false
    var bedtimeHour: Int = 22
    var bedtimeMinute: Int = 0

    // Blood pressure reminder times (minutes since midnight) and active weekdays (1...7)
    var bpTimes: [Int] = []
    var bpActiveWeekdays: Set<Int> = []

    // Glucose reminder toggles
    var enableBeforeMeal: Bool = true
    var enableAfterMeal2h: Bool = true
    var enableDailyCycleMode: Bool = false {
        didSet {
            guard oldValue != enableDailyCycleMode else { return }
            syncDailyCycleDisplaySlot()
        }
    }
    private var currentCycleIndex: Int = 0
    private var dailyCycleAnchorDate: Date? = nil
    /// Per-day step overrides, mirroring `UserSettings.cycleOverrides`. Written by
    /// `applyDailyCycleTarget` / `switchDailyCycleTargetForward`; never mutates the anchor.
    private var cycleOverrides: [String: Int] = [:]
    private(set) var dailyCycleDisplaySlot: MealSlot? = nil

    var dailyCycleCurrentSlotTitle: String {
        guard enableDailyCycleMode, let slot = dailyCycleDisplaySlot else { return "—" }
        return cycleSlotTitle(slot)
    }

    var dailyCycleSwitchTitle: String {
        let next = dailyCycleNextSlot()
        return L10n.settingsRowDailyCycleSwitchTo(cycleSlotTitle(next))
    }

    // Thresholds
    var bpSystolicMin: Int = 90
    var bpSystolicMax: Int = 140
    var bpDiastolicMin: Int = 60
    var bpDiastolicMax: Int = 90

    var glucoseMin: Double = 3.9
    var glucoseMax: Double = 7.8

    // MARK: - Google integration
    var isGoogleEnabled: Bool = false
    var googleSummary: String = L10n.settingsGoogleSummaryNotConnected

    // Export state
    var isExporting: Bool = false

    // MARK: - Sync status
    var pendingCount: Int = 0
    var failedCount: Int = 0
    var lastSyncAt: Date? = nil
    var isLikelyRestoringFromICloud: Bool = false
    private let restoreHintUntil = Date().addingTimeInterval(120)
    private var googleSyncLifecycleObserver: NSObjectProtocol?
    private var measurementsDidChangeObserver: NSObjectProtocol?
    private var syncStatusRefreshDebounceTask: Task<Void, Never>?
    private var autoSaveDebounceTask: Task<Void, Never>?
    private var hasFinishedInitialLoad: Bool = false
    private var isSavingSettings: Bool = false
    private var hasQueuedSaveRequest: Bool = false
    var isSwitchingCycleTarget: Bool = false

    // MARK: - Init
    init(
        settingsRepository: any SettingsRepository,
        googleIntegrationRepository: any GoogleIntegrationRepository,
        exportCSVUseCase: ExportCSVUseCase,
        measurementsRepository: any MeasurementsRepository,
        googleSheetsClient: any GoogleSheetsClient,
        analyticsRepository: any AnalyticsRepository,
        schedulesUpdater: any SchedulesUpdating,
        googleSignIn: @escaping @MainActor () async throws -> GoogleOAuthTokens = GoogleOAuth.signIn
    ) {
        self.settingsRepository = settingsRepository
        self.googleIntegrationRepository = googleIntegrationRepository
        self.exportCSVUseCase = exportCSVUseCase
        self.measurementsRepository = measurementsRepository
        self.googleSheetsClient = googleSheetsClient
        self.analyticsRepository = analyticsRepository
        self.schedulesUpdater = schedulesUpdater
        self.googleSignIn = googleSignIn
        observeGoogleSyncLifecycle()
        observeMeasurementsDidChange()
    }

    @MainActor
    deinit {
        if let observer = googleSyncLifecycleObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = measurementsDidChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        syncStatusRefreshDebounceTask?.cancel()
        autoSaveDebounceTask?.cancel()
    }

    // MARK: - Public API
    func loadSettings() async {
        isLoading = true
        hasFinishedInitialLoad = false
        autoSaveDebounceTask?.cancel()
        defer { isLoading = false }
        do {
            let settings = try await settingsRepository.getOrCreate()
            self.settingsModel = settings
            // Map models -> VM properties
            glucoseUnit = settings.glucoseUnit

            breakfastHour = settings.breakfastHour
            breakfastMinute = settings.breakfastMinute
            lunchHour = settings.lunchHour
            lunchMinute = settings.lunchMinute
            dinnerHour = settings.dinnerHour
            dinnerMinute = settings.dinnerMinute
            bedtimeSlotEnabled = settings.bedtimeSlotEnabled
            bedtimeHour = settings.bedtimeHour
            bedtimeMinute = settings.bedtimeMinute

            bpTimes = settings.bpTimes
            bpActiveWeekdays = settings.bpActiveWeekdays

            enableBeforeMeal = settings.enableBeforeMeal
            enableAfterMeal2h = settings.enableAfterMeal2h
            currentCycleIndex = settings.currentCycleIndex
            dailyCycleAnchorDate = settings.dailyCycleAnchorDate
            cycleOverrides = settings.cycleOverrides
            enableDailyCycleMode = settings.enableDailyCycleMode
            syncDailyCycleDisplaySlot()

            bpSystolicMin = settings.bpSystolicMin
            bpSystolicMax = settings.bpSystolicMax
            bpDiastolicMin = settings.bpDiastolicMin
            bpDiastolicMax = settings.bpDiastolicMax

            glucoseMin = settings.glucoseMin
            glucoseMax = settings.glucoseMax

            // Enable autosave as soon as editable settings are hydrated.
            hasFinishedInitialLoad = true

            // Google
            await refreshSyncStatus()
        } catch {
            handleError(error, context: "loadSettings", policy: .showErrorDescription)
        }
    }

    func saveSettings() async {
        await enqueueSettingsSave()
    }

    func scheduleAutoSave() {
        guard hasFinishedInitialLoad else { return }

        autoSaveDebounceTask?.cancel()
        autoSaveDebounceTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await self.enqueueSettingsSave()
        }
    }

    var autoSaveSignature: String {
        let weekdaysSignature = bpActiveWeekdays.sorted().map(String.init).joined(separator: ",")
        let bpTimesSignature = bpTimes.map(String.init).joined(separator: ",")
        return [
            glucoseUnit.rawValue,
            "\(breakfastHour):\(breakfastMinute)",
            "\(lunchHour):\(lunchMinute)",
            "\(dinnerHour):\(dinnerMinute)",
            "\(bedtimeHour):\(bedtimeMinute)",
            "\(bedtimeSlotEnabled)",
            bpTimesSignature,
            weekdaysSignature,
            "\(enableBeforeMeal)",
            "\(enableAfterMeal2h)",
            "\(enableDailyCycleMode)",
            "\(bpSystolicMin)",
            "\(bpSystolicMax)",
            "\(bpDiastolicMin)",
            "\(bpDiastolicMax)",
            "\(glucoseMin.bitPattern)",
            "\(glucoseMax.bitPattern)"
        ].joined(separator: "|")
    }

    func glucoseThresholdRangeForCurrentUnit() -> ClosedRange<Double> {
        switch glucoseUnit {
        case .mmolL:
            return GlucoseConstraints.mmolRange
        case .mgdL:
            let low = GlucoseConstraints.mmolRange.lowerBound * mgdLPerMmolL
            let high = GlucoseConstraints.mmolRange.upperBound * mgdLPerMmolL
            return low...high
        }
    }

    func glucoseThresholdStepForCurrentUnit() -> Double {
        switch glucoseUnit {
        case .mmolL:
            return 0.1
        case .mgdL:
            return 1
        }
    }

    func displayGlucoseThreshold(_ valueInMmol: Double) -> Double {
        switch glucoseUnit {
        case .mmolL:
            return valueInMmol
        case .mgdL:
            return (valueInMmol * mgdLPerMmolL).rounded()
        }
    }

    func storedGlucoseThreshold(_ displayedValue: Double) -> Double {
        switch glucoseUnit {
        case .mmolL:
            return displayedValue
        case .mgdL:
            return displayedValue / mgdLPerMmolL
        }
    }

    func dailyCycleSwitchTargets(today: Date = Date()) -> [MealSlot] {
        guard enableDailyCycleMode else { return [] }
        var order: [MealSlot] = [.breakfast, .lunch, .dinner, .none]
        if !bedtimeSlotEnabled {
            order.removeAll { $0 == .none }
        }
        let current = dailyCycleCurrentSlot(today: today) ?? .breakfast
        return order.filter { $0 != current }
    }

    func cycleSlotTitle(_ slot: MealSlot) -> String {
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

    func applyDailyCycleTarget(_ mealSlot: MealSlot, today: Date = Date()) async {
        guard enableDailyCycleMode else { return }
        guard !isSwitchingCycleTarget else { return }
        guard dailyCycleSwitchTargets(today: today).contains(mealSlot) else { return }
        guard let targetStep = cycleStep(for: mealSlot) else { return }

        isSwitchingCycleTarget = true
        defer { isSwitchingCycleTarget = false }

        let calendar = Calendar.current
        let key = GlucoseCyclePlanner.dateKey(for: today, calendar: calendar)
        cycleOverrides = GlucoseCyclePlanner.pruneOverrides(cycleOverrides, today: today, calendar: calendar)
        cycleOverrides[key] = targetStep.rawValue
        dailyCycleDisplaySlot = mealSlot
        await enqueueSettingsSave()
    }

    private func enqueueSettingsSave() async {
        if isSavingSettings {
            hasQueuedSaveRequest = true
            return
        }

        repeat {
            hasQueuedSaveRequest = false
            isSavingSettings = true
            await persistSettings()
            isSavingSettings = false
        } while hasQueuedSaveRequest
    }

    private func persistSettings() async {
        do {
            let settings = try await resolveSettingsModel()
            // Map VM -> model
            settings.glucoseUnit = glucoseUnit

            settings.breakfastHour = breakfastHour
            settings.breakfastMinute = breakfastMinute
            settings.lunchHour = lunchHour
            settings.lunchMinute = lunchMinute
            settings.dinnerHour = dinnerHour
            settings.dinnerMinute = dinnerMinute
            settings.bedtimeSlotEnabled = bedtimeSlotEnabled
            settings.bedtimeHour = bedtimeHour
            settings.bedtimeMinute = bedtimeMinute

            settings.bpTimes = bpTimes
            settings.bpActiveWeekdays = bpActiveWeekdays

            settings.enableBeforeMeal = enableBeforeMeal
            settings.enableAfterMeal2h = enableAfterMeal2h
            settings.enableDailyCycleMode = enableDailyCycleMode
            if enableDailyCycleMode {
                settings.currentCycleIndex = currentCycleIndex
                // Set anchor once when first enabled; never overwrite an existing anchor.
                if dailyCycleAnchorDate == nil {
                    dailyCycleAnchorDate = GlucoseCyclePlanner.fallbackAnchorDate(
                        currentCycleIndex: currentCycleIndex
                    )
                }
                settings.dailyCycleAnchorDate = dailyCycleAnchorDate
                settings.cycleOverrides = cycleOverrides
            } else {
                settings.dailyCycleAnchorDate = nil
                settings.cycleOverrides = [:]
                cycleOverrides = [:]
            }

            settings.bpSystolicMin = bpSystolicMin
            settings.bpSystolicMax = bpSystolicMax
            settings.bpDiastolicMin = bpDiastolicMin
            settings.bpDiastolicMax = bpDiastolicMax

            settings.glucoseMin = glucoseMin
            settings.glucoseMax = glucoseMax

            try await settingsRepository.save(settings)
            errorMessage = nil
            do {
                try await schedulesUpdater.scheduleFromCurrentSettings()
            } catch {
                // Saving settings already succeeded; surface scheduling failure without rolling back saved values.
                handleError(
                    error,
                    context: "saveSettings.scheduleFromCurrentSettings",
                    policy: .showMessage(L10n.settingsErrorSavedButRemindersNotUpdated)
                )
            }
            NotificationCenter.default.post(name: .settingsDidSave, object: nil)
        } catch {
            handleError(error, context: "persistSettings", policy: .showErrorDescription)
        }
    }

    func switchDailyCycleTargetForward(today: Date = Date()) {
        guard enableDailyCycleMode else { return }
        let calendar = Calendar.current
        let referenceDay = calendar.startOfDay(for: today)
        let anchor = dailyCycleAnchorDate
            ?? GlucoseCyclePlanner.fallbackAnchorDate(
                currentCycleIndex: currentCycleIndex,
                referenceDate: today,
                calendar: calendar
            )
        let currentStep = GlucoseCyclePlanner.step(
            on: referenceDay, anchorDate: anchor, overrides: cycleOverrides, calendar: calendar
        )
        let nextStepIndex = (currentStep.rawValue + 1) % GlucoseCycleStep.allCases.count
        let key = GlucoseCyclePlanner.dateKey(for: today, calendar: calendar)
        cycleOverrides = GlucoseCyclePlanner.pruneOverrides(cycleOverrides, today: today, calendar: calendar)
        cycleOverrides[key] = nextStepIndex
        syncDailyCycleDisplaySlot(today: today)
    }

    func applyDailyCycleTargetForward(today: Date = Date()) async {
        guard enableDailyCycleMode else { return }
        switchDailyCycleTargetForward(today: today)

        do {
            let settings = try await resolveSettingsModel()
            settings.enableDailyCycleMode = true
            settings.currentCycleIndex = currentCycleIndex
            // Set anchor once if not yet initialised; never overwrite an existing anchor.
            if dailyCycleAnchorDate == nil {
                dailyCycleAnchorDate = GlucoseCyclePlanner.fallbackAnchorDate(
                    currentCycleIndex: currentCycleIndex,
                    referenceDate: today,
                    calendar: Calendar.current
                )
            }
            settings.dailyCycleAnchorDate = dailyCycleAnchorDate
            settings.cycleOverrides = cycleOverrides

            try await settingsRepository.save(settings)
            errorMessage = nil
            do {
                try await schedulesUpdater.scheduleFromCurrentSettings()
            } catch {
                handleError(
                    error,
                    context: "applyDailyCycleTargetForward.scheduleFromCurrentSettings",
                    policy: .showMessage(L10n.settingsErrorSavedButRemindersNotUpdated)
                )
            }
            NotificationCenter.default.post(name: .settingsDidSave, object: nil)
        } catch {
            handleError(error, context: "applyDailyCycleTargetForward", policy: .showErrorDescription)
        }
    }

    func syncDailyCycleDisplaySlot(today: Date = Date()) {
        dailyCycleDisplaySlot = dailyCycleCurrentSlot(today: today)
    }

    func connectGoogle() async -> Bool {
        do {
            let integration = try await fetchLatestGoogleIntegrationModel()
            googleSummary = L10n.settingsGoogleStartingSignIn

            let tokens = try await googleSignIn()

            integration.isEnabled = true
            integration.googleUserId = GoogleIDToken.userIdentifier(from: tokens.idToken)

            // Create spreadsheet if missing
            if integration.spreadsheetId == nil {
                let title = L10n.settingsGoogleSpreadsheetTitle
                do {
                    let id = try await resolveSpreadsheetId(
                        refreshToken: tokens.refreshToken,
                        title: title,
                        knownTitles: L10n.settingsGoogleSpreadsheetKnownTitles
                    )
                    integration.spreadsheetId = id
                } catch {
                    // Surface error but keep tokens saved; user can retry later
                    handleError(
                        error,
                        context: "connectGoogle.createSpreadsheet",
                        policy: .showMessage(L10n.settingsGoogleSpreadsheetCreationFailed(error.localizedDescription))
                    )
                }
            }

            try await googleIntegrationRepository.setRefreshToken(tokens.refreshToken)
            try await googleIntegrationRepository.update(integration)
            await refreshSyncStatus()
            await analyticsRepository.logGoogleEnabled()
            errorMessage = nil
            return true
        } catch {
            handleError(error, context: "connectGoogle", policy: .showErrorDescription)
            return false
        }
    }

    func connectGoogleAndSync(initialSync: @escaping @MainActor () async -> Void) async {
        isGoogleOperationInProgress = true
        googleSummary = L10n.settingsGoogleStartingSignIn

        let connected = await connectGoogle()
        guard connected else {
            isGoogleOperationInProgress = false
            await refreshSyncStatus()
            return
        }

        googleSummary = L10n.settingsGoogleSummarySyncing
        await initialSync()

        isGoogleOperationInProgress = false
        await refreshSyncStatus()
    }

    func disconnectGoogle() async {
        do {
            let integration = try await fetchLatestGoogleIntegrationModel()
            try await googleIntegrationRepository.clearTokens(integration)
            await refreshSyncStatus()
            await analyticsRepository.logGoogleDisabled()
        } catch {
            handleError(error, context: "disconnectGoogle", policy: .showErrorDescription)
        }
    }

    func refreshCloudBackedState() async {
        await refreshSyncStatus()
    }

    func exportCSV(from: Date, to: Date, includeBP: Bool, includeGlucose: Bool) async -> URL? {
        isExporting = true
        defer { isExporting = false }
        do {
            let url = try await exportCSVUseCase.exportCSV(from: from, to: to, includeBP: includeBP, includeGlucose: includeGlucose)
            await analyticsRepository.logExportCSV()
            return url
        } catch {
            handleError(error, context: "exportCSV", policy: .showErrorDescription)
            return nil
        }
    }

    // MARK: - Helpers
    private func resolveSettingsModel() async throws -> UserSettings {
        if let s = settingsModel { return s }
        let s = try await settingsRepository.getOrCreate()
        settingsModel = s
        return s
    }

    private func resolveSpreadsheetId(refreshToken: String, title: String, knownTitles: [String]) async throws -> String {
        var lookupTitles: [String] = [title]
        for knownTitle in knownTitles where !lookupTitles.contains(knownTitle) {
            lookupTitles.append(knownTitle)
        }

        for lookupTitle in lookupTitles {
            guard let existingId = try await googleSheetsClient.findSpreadsheetIdByTitle(
                refreshToken: refreshToken,
                title: lookupTitle
            ) else {
                continue
            }
            logger.info("Reused spreadsheet id=\(existingId, privacy: .public)")
            return existingId
        }

        let createdId = try await googleSheetsClient.createSpreadsheetAndSetup(refreshToken: refreshToken, title: title)
        logger.info("Created spreadsheet id=\(createdId, privacy: .public)")
        return createdId
    }

    private func fetchLatestGoogleIntegrationModel() async throws -> GoogleIntegration {
        let integration = try await googleIntegrationRepository.getOrCreate()
        googleIntegrationModel = integration
        return integration
    }

    private func updateGoogleSummary(using integration: GoogleIntegration, hasRefreshToken: Bool) {
        let enabled = integration.isEnabled
        let hasCreds = hasRefreshToken && integration.spreadsheetId != nil
        isGoogleEnabled = enabled && hasCreds
        if !enabled {
            googleSummary = L10n.settingsGoogleSummaryNotConnected
        } else if let uid = integration.googleUserId, hasCreds {
            googleSummary = L10n.settingsGoogleSummaryConnected(uid: uid)
        } else if hasCreds {
            googleSummary = L10n.settingsGoogleSummaryConnected
        } else {
            googleSummary = L10n.settingsGoogleSummaryAwaitingCredentials
        }
    }

    private func observeGoogleSyncLifecycle() {
        googleSyncLifecycleObserver = NotificationCenter.default.addObserver(
            forName: .googleSyncLifecycleChanged,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let rawPhase = notification.userInfo?[GoogleSyncLifecycleUserInfoKey.phase.rawValue] as? String,
                  let phase = GoogleSyncLifecyclePhase(rawValue: rawPhase)
            else {
                return
            }

            let snapshot = GoogleSyncStatusSnapshot(
                pendingCount: notification.userInfo?[GoogleSyncLifecycleUserInfoKey.pendingCount.rawValue] as? Int,
                failedCount: notification.userInfo?[GoogleSyncLifecycleUserInfoKey.failedCount.rawValue] as? Int,
                lastSyncAt: notification.userInfo?[GoogleSyncLifecycleUserInfoKey.lastSyncAt.rawValue] as? Date
            )
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.handleGoogleSyncLifecycle(phase, snapshot: snapshot)
            }
        }
    }

    private func observeMeasurementsDidChange() {
        measurementsDidChangeObserver = NotificationCenter.default.addObserver(
            forName: .measurementsDidChange,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleSyncStatusRefreshDebounced()
            }
        }
    }

    private func scheduleSyncStatusRefreshDebounced() {
        guard !isGoogleSyncInProgress else { return }

        syncStatusRefreshDebounceTask?.cancel()
        syncStatusRefreshDebounceTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            await self.refreshSyncStatus()
        }
    }

    private func handleGoogleSyncLifecycle(_ phase: GoogleSyncLifecyclePhase, snapshot: GoogleSyncStatusSnapshot) async {
        switch phase {
        case .started:
            isGoogleSyncInProgress = true
            googleSummary = L10n.settingsGoogleSummarySyncing
            applyGoogleSyncStatusSnapshot(snapshot)
        case .progress:
            applyGoogleSyncStatusSnapshot(snapshot)
        case .finished:
            isGoogleSyncInProgress = false
            applyGoogleSyncStatusSnapshot(snapshot)
            await refreshSyncStatus()
        }
    }

    private struct GoogleSyncStatusSnapshot {
        let pendingCount: Int?
        let failedCount: Int?
        let lastSyncAt: Date?
    }

    private func applyGoogleSyncStatusSnapshot(_ snapshot: GoogleSyncStatusSnapshot) {
        if let pendingCount = snapshot.pendingCount {
            self.pendingCount = pendingCount
        }
        if let failedCount = snapshot.failedCount {
            self.failedCount = failedCount
        }
        if let snapshotLastSyncAt = snapshot.lastSyncAt {
            if let currentLastSyncAt = lastSyncAt {
                lastSyncAt = max(currentLastSyncAt, snapshotLastSyncAt)
            } else {
                lastSyncAt = snapshotLastSyncAt
            }
        }
    }

    func refreshSyncStatus() async {
        do {
            let integration = try await fetchLatestGoogleIntegrationModel()
            let hasRefreshToken = (try await googleIntegrationRepository.getRefreshToken()) != nil
            // Fetch pending or failed items per type
            let pendingOrFailedBP = try await measurementsRepository.pendingOrFailedBPSync()
            let pendingOrFailedGlucose = try await measurementsRepository.pendingOrFailedGlucoseSync()

            // Compute counts by status across both types
            let bpPending = pendingOrFailedBP.filter { $0.googleSyncStatus == .pending }.count
            let glPending = pendingOrFailedGlucose.filter { $0.googleSyncStatus == .pending }.count
            let bpFailed = pendingOrFailedBP.filter { $0.googleSyncStatus == .failed }.count
            let glFailed = pendingOrFailedGlucose.filter { $0.googleSyncStatus == .failed }.count

            pendingCount = bpPending + glPending
            failedCount = bpFailed + glFailed

            // Compute last sync date from all measurements
            let allBP = try await measurementsRepository.bpMeasurements(from: .distantPast, to: .distantFuture)
            let allGlucose = try await measurementsRepository.glucoseMeasurements(from: .distantPast, to: .distantFuture)

            let bpLastSyncDates = allBP.compactMap { $0.googleLastSyncAt }
            let glucoseLastSyncDates = allGlucose.compactMap { $0.googleLastSyncAt }
            let allSyncDates = bpLastSyncDates + glucoseLastSyncDates

            lastSyncAt = allSyncDates.max()
            if !isGoogleBusy {
                updateGoogleSummary(using: integration, hasRefreshToken: hasRefreshToken)
            }
            let totalMeasurementsCount = allBP.count + allGlucose.count
            updateRestoreHintState(totalMeasurementsCount: totalMeasurementsCount, hasRefreshToken: hasRefreshToken)
        } catch {
            handleError(error, context: "refreshSyncStatus", policy: .suppressed)
        }
    }

    private func updateRestoreHintState(totalMeasurementsCount: Int, hasRefreshToken: Bool) {
        let withinRestoreWindow = Date() < restoreHintUntil
        let hasAnyMeasurements = totalMeasurementsCount > 0
        let hasCloudMarkers = hasAnyGoogleCloudData(googleIntegrationModel, hasRefreshToken: hasRefreshToken)

        isLikelyRestoringFromICloud = withinRestoreWindow && !hasAnyMeasurements && !hasCloudMarkers
    }

    private func hasAnyGoogleCloudData(_ integration: GoogleIntegration?, hasRefreshToken: Bool) -> Bool {
        guard let integration else { return false }
        return integration.isEnabled
            || hasRefreshToken
            || hasNonEmpty(integration.spreadsheetId)
            || hasNonEmpty(integration.googleUserId)
    }

    private func hasNonEmpty(_ value: String?) -> Bool {
        guard let value else { return false }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func dailyCycleCurrentSlot(today: Date = Date()) -> MealSlot? {
        guard enableDailyCycleMode else { return nil }
        let calendar = Calendar.current
        let anchor = dailyCycleAnchorDate
            ?? GlucoseCyclePlanner.fallbackAnchorDate(
                currentCycleIndex: currentCycleIndex,
                referenceDate: today,
                calendar: calendar
            )
        let step = GlucoseCyclePlanner.step(
            on: today, anchorDate: anchor, overrides: cycleOverrides, calendar: calendar
        )
        return cycleSlot(for: step)
    }

    func dailyCycleNextSlot(today: Date = Date()) -> MealSlot {
        let order: [MealSlot] = [.breakfast, .lunch, .dinner, .none]
        let current = dailyCycleCurrentSlot(today: today) ?? .breakfast
        guard let currentIndex = order.firstIndex(of: current) else { return .lunch }
        let nextIndex = (currentIndex + 1) % order.count
        return order[nextIndex]
    }

    private func cycleSlot(for step: GlucoseCycleStep) -> MealSlot {
        switch step {
        case .breakfastDay:
            return .breakfast
        case .lunchDay:
            return .lunch
        case .dinnerDay:
            return .dinner
        case .bedtimeDay:
            return .none
        }
    }

    private func cycleStep(for slot: MealSlot) -> GlucoseCycleStep? {
        switch slot {
        case .breakfast:
            return .breakfastDay
        case .lunch:
            return .lunchDay
        case .dinner:
            return .dinnerDay
        case .none:
            return .bedtimeDay
        }
    }

    private func handleError(_ error: Error, context: String, policy: UserSurfacePolicy) {
        logger.error(
            "\(context, privacy: .public) failed. user_surface=\(policy.loggingValue, privacy: .public) error=\(String(describing: error), privacy: .public)"
        )

        switch policy {
        case .suppressed:
            return
        case .showErrorDescription:
            errorMessage = (error as NSError).localizedDescription
        case .showMessage(let message):
            errorMessage = message
        }
    }
}
