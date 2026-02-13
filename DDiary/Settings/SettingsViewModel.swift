import Foundation
import Observation

extension Notification.Name {
    nonisolated static let settingsDidSave = Notification.Name("SettingsDidSave")
}

@MainActor
@Observable
final class SettingsViewModel {
    // MARK: - Dependencies
    private let settingsRepository: any SettingsRepository
    private let googleIntegrationRepository: any GoogleIntegrationRepository
    private let exportCSVUseCase: ExportCSVUseCase
    private let measurementsRepository: any MeasurementsRepository
    private let googleSheetsClient: any GoogleSheetsClient
    private let schedulesUpdater: any SchedulesUpdating

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
    }

    @MainActor
    deinit {
        if let observer = googleSyncLifecycleObserver {
            NotificationCenter.default.removeObserver(observer)
        }
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

            bpSystolicMin = settings.bpSystolicMin
            bpSystolicMax = settings.bpSystolicMax
            bpDiastolicMin = settings.bpDiastolicMin
            bpDiastolicMax = settings.bpDiastolicMax

            glucoseMin = settings.glucoseMin
            glucoseMax = settings.glucoseMax

            // Google
            await refreshSyncStatus()
        } catch {
            errorMessage = String(describing: error)
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
                errorMessage = L10n.settingsErrorSavedButRemindersNotUpdated
            }
            NotificationCenter.default.post(name: .settingsDidSave, object: nil)
        } catch {
            errorMessage = String(describing: error)
        }
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
                    log("Created spreadsheet id=\(id)")
                } catch {
                    // Surface error but keep tokens saved; user can retry later
                    self.errorMessage = L10n.settingsGoogleSpreadsheetCreationFailed(error.localizedDescription)
                    log("Spreadsheet creation failed: \(error)")
                }
            }

            try await googleIntegrationRepository.update(integration)
            await refreshSyncStatus()
            errorMessage = nil
            return true
        } catch {
            errorMessage = String(describing: error)
            log("Google connect failed: \(error)")
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
            errorMessage = String(describing: error)
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
            errorMessage = String(describing: error)
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
            guard let rawPhase = notification.userInfo?["phase"] as? String,
                  let phase = GoogleSyncLifecyclePhase(rawValue: rawPhase)
            else {
                return
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.handleGoogleSyncLifecycle(phase)
            }
        }
    }

    private func handleGoogleSyncLifecycle(_ phase: GoogleSyncLifecyclePhase) async {
        switch phase {
        case .started:
            isGoogleSyncInProgress = true
            googleSummary = L10n.settingsGoogleSummarySyncing
            await refreshSyncStatus()
        case .progress:
            await refreshSyncStatus()
        case .finished:
            isGoogleSyncInProgress = false
            await refreshSyncStatus()
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
            // On error, keep current values but optionally clear errorMessage
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

    private func log(_ message: String) {
        #if DEBUG
        print("[Settings] \(message)")
        #endif
    }
}
