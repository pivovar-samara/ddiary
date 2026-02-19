import Foundation
import Observation
import OSLog

extension Notification.Name {
    nonisolated static let settingsDidSave = Notification.Name("SettingsDidSave")
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
    private let schedulesUpdater: any SchedulesUpdating
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "DDiary",
        category: "SettingsViewModel"
    )

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
    var enableBedtime: Bool = false
    var enableDailyCycleMode: Bool = false
    private var currentCycleIndex: Int = 0
    private var dailyCycleAnchorDate: Date? = nil

    var dailyCycleCurrentSlotTitle: String {
        guard let slot = dailyCycleCurrentSlot() else { return "—" }
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

    // MARK: - Init
    init(
        settingsRepository: any SettingsRepository,
        googleIntegrationRepository: any GoogleIntegrationRepository,
        exportCSVUseCase: ExportCSVUseCase,
        measurementsRepository: any MeasurementsRepository,
        googleSheetsClient: any GoogleSheetsClient,
        schedulesUpdater: any SchedulesUpdating
    ) {
        self.settingsRepository = settingsRepository
        self.googleIntegrationRepository = googleIntegrationRepository
        self.exportCSVUseCase = exportCSVUseCase
        self.measurementsRepository = measurementsRepository
        self.googleSheetsClient = googleSheetsClient
        self.schedulesUpdater = schedulesUpdater
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
    }

    // MARK: - Public API
    func loadSettings() async {
        isLoading = true
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
            enableBedtime = settings.enableBedtime
            enableDailyCycleMode = settings.enableDailyCycleMode
            currentCycleIndex = settings.currentCycleIndex
            dailyCycleAnchorDate = settings.dailyCycleAnchorDate

            bpSystolicMin = settings.bpSystolicMin
            bpSystolicMax = settings.bpSystolicMax
            bpDiastolicMin = settings.bpDiastolicMin
            bpDiastolicMax = settings.bpDiastolicMax

            glucoseMin = settings.glucoseMin
            glucoseMax = settings.glucoseMax

            // Google
            await refreshSyncStatus()
        } catch {
            handleError(error, context: "loadSettings", policy: .showErrorDescription)
        }
    }

    func saveSettings() async {
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
            settings.enableBedtime = enableBedtime
            settings.enableDailyCycleMode = enableDailyCycleMode
            if enableDailyCycleMode {
                settings.currentCycleIndex = currentCycleIndex
                if dailyCycleAnchorDate == nil {
                    dailyCycleAnchorDate = GlucoseCyclePlanner.fallbackAnchorDate(
                        currentCycleIndex: currentCycleIndex
                    )
                }
                settings.dailyCycleAnchorDate = dailyCycleAnchorDate
            } else {
                settings.dailyCycleAnchorDate = nil
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
            handleError(error, context: "saveSettings", policy: .showErrorDescription)
        }
    }

    func switchDailyCycleTargetForward(today: Date = Date()) {
        guard enableDailyCycleMode else { return }
        let calendar = Calendar.current
        let referenceDay = calendar.startOfDay(for: today)
        let anchorDate = dailyCycleAnchorDate
            ?? GlucoseCyclePlanner.fallbackAnchorDate(
                currentCycleIndex: currentCycleIndex,
                referenceDate: today,
                calendar: calendar
            )
        let shiftedAnchor = calendar.date(byAdding: .day, value: -1, to: anchorDate) ?? anchorDate
        dailyCycleAnchorDate = shiftedAnchor
        currentCycleIndex = GlucoseCyclePlanner.step(on: referenceDay, anchorDate: shiftedAnchor, calendar: calendar).rawValue
    }

    func connectGoogle() async -> Bool {
        do {
            let integration = try await fetchLatestGoogleIntegrationModel()
            googleSummary = L10n.settingsGoogleStartingSignIn

            let tokens = try await GoogleOAuth.signIn()

            integration.isEnabled = true
            integration.refreshToken = tokens.refreshToken
            integration.googleUserId = GoogleIDToken.userIdentifier(from: tokens.idToken)

            // Create spreadsheet if missing
            if integration.spreadsheetId == nil {
                let title = L10n.settingsGoogleSpreadsheetTitle
                do {
                    let id = try await googleSheetsClient.createSpreadsheetAndSetup(refreshToken: tokens.refreshToken, title: title)
                    integration.spreadsheetId = id
                    logger.info("Created spreadsheet id=\(id, privacy: .public)")
                } catch {
                    // Surface error but keep tokens saved; user can retry later
                    handleError(
                        error,
                        context: "connectGoogle.createSpreadsheet",
                        policy: .showMessage(L10n.settingsGoogleSpreadsheetCreationFailed(error.localizedDescription))
                    )
                }
            }

            try await googleIntegrationRepository.update(integration)
            await refreshSyncStatus()
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

    private func fetchLatestGoogleIntegrationModel() async throws -> GoogleIntegration {
        let integration = try await googleIntegrationRepository.getOrCreate()
        googleIntegrationModel = integration
        return integration
    }

    private func updateGoogleSummary(using integration: GoogleIntegration) {
        let enabled = integration.isEnabled
        let hasCreds = integration.refreshToken != nil && integration.spreadsheetId != nil
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
                updateGoogleSummary(using: integration)
            }
            let totalMeasurementsCount = allBP.count + allGlucose.count
            updateRestoreHintState(totalMeasurementsCount: totalMeasurementsCount)
        } catch {
            handleError(error, context: "refreshSyncStatus", policy: .suppressed)
        }
    }

    private func updateRestoreHintState(totalMeasurementsCount: Int) {
        let withinRestoreWindow = Date() < restoreHintUntil
        let hasAnyMeasurements = totalMeasurementsCount > 0
        let hasCloudMarkers = hasAnyGoogleCloudData(googleIntegrationModel)

        isLikelyRestoringFromICloud = withinRestoreWindow && !hasAnyMeasurements && !hasCloudMarkers
    }

    private func hasAnyGoogleCloudData(_ integration: GoogleIntegration?) -> Bool {
        guard let integration else { return false }
        return integration.isEnabled
            || hasNonEmpty(integration.refreshToken)
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
        let step = GlucoseCyclePlanner.step(on: today, anchorDate: anchor, calendar: calendar)
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

    private func cycleSlotTitle(_ slot: MealSlot) -> String {
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
