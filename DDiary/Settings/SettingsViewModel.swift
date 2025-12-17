import Foundation
import Observation

@MainActor
@Observable
final class SettingsViewModel {
    // MARK: - Dependencies
    private let settingsRepository: any SettingsRepository
    private let googleIntegrationRepository: any GoogleIntegrationRepository
    private let exportCSVUseCase: ExportCSVUseCase

    // MARK: - Backing models (MainActor-bound)
    private var settingsModel: UserSettings?
    private var googleIntegrationModel: GoogleIntegration?

    // MARK: - UI State
    var isLoading: Bool = false
    var errorMessage: String? = nil

    // MARK: - UserSettings mirrors
    var glucoseUnit: GlucoseUnit = .mmolL

    var breakfastHour: Int = 8
    var breakfastMinute: Int = 0
    var lunchHour: Int = 13
    var lunchMinute: Int = 0
    var dinnerHour: Int = 19
    var dinnerMinute: Int = 0
    var bedtimeSlotEnabled: Bool = false

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
    var googleSummary: String = "Not connected"

    // Export state
    var isExporting: Bool = false

    // MARK: - Init
    init(
        settingsRepository: any SettingsRepository,
        googleIntegrationRepository: any GoogleIntegrationRepository,
        exportCSVUseCase: ExportCSVUseCase
    ) {
        self.settingsRepository = settingsRepository
        self.googleIntegrationRepository = googleIntegrationRepository
        self.exportCSVUseCase = exportCSVUseCase
    }

    // MARK: - Public API
    func loadSettings() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let settings = try await settingsRepository.getOrCreate()
            let integration = try await googleIntegrationRepository.getOrCreate()
            self.settingsModel = settings
            self.googleIntegrationModel = integration
            // Map models -> VM properties
            glucoseUnit = settings.glucoseUnit

            breakfastHour = settings.breakfastHour
            breakfastMinute = settings.breakfastMinute
            lunchHour = settings.lunchHour
            lunchMinute = settings.lunchMinute
            dinnerHour = settings.dinnerHour
            dinnerMinute = settings.dinnerMinute
            bedtimeSlotEnabled = settings.bedtimeSlotEnabled

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
            updateGoogleSummary(using: integration)
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
            await updateSchedulesAfterSave()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func connectGoogle() async {
        // Stub: demonstrate structure for OAuth-based connection.
        // In production, launch ASWebAuthenticationSession to obtain tokens, then persist via repository.
        do {
            let integration = try await resolveGoogleIntegrationModel()
            googleSummary = "Starting Google sign-in… (stub)"
            // TODO: Implement OAuth via ASWebAuthenticationSession.
            // On success:
            // integration.isEnabled = true
            // integration.refreshToken = <token>
            // integration.spreadsheetId = <spreadsheet>
            // integration.googleUserId = <user id>
            // try await googleIntegrationRepository.update(integration)
            // updateGoogleSummary(using: integration)

            // For now, just reset summary to current persisted state
            updateGoogleSummary(using: integration)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func disconnectGoogle() async {
        do {
            let integration = try await resolveGoogleIntegrationModel()
            try await googleIntegrationRepository.clearTokens(integration)
            updateGoogleSummary(using: integration)
        } catch {
            errorMessage = String(describing: error)
        }
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

    private func resolveGoogleIntegrationModel() async throws -> GoogleIntegration {
        if let g = googleIntegrationModel { return g }
        let g = try await googleIntegrationRepository.getOrCreate()
        googleIntegrationModel = g
        return g
    }

    private func updateGoogleSummary(using integration: GoogleIntegration) {
        let enabled = integration.isEnabled
        let hasCreds = integration.refreshToken != nil && integration.spreadsheetId != nil
        isGoogleEnabled = enabled && hasCreds
        if !enabled {
            googleSummary = "Not connected"
        } else if let uid = integration.googleUserId, hasCreds {
            googleSummary = "Connected (\(uid))"
        } else if hasCreds {
            googleSummary = "Connected"
        } else {
            googleSummary = "Enabled, awaiting credentials"
        }
    }

    private func updateSchedulesAfterSave() async {
        // Reschedule notifications after settings changes.
        // In v1, we do this best-effort and ignore errors.
        // The container is not directly available here, so expose a hook via NotificationsRepository if needed.
        // For simplicity, fetch current settings and reschedule via a global environment.
        // In a larger app, inject an UpdateSchedulesUseCase into this VM.
        do {
            _ = try await settingsRepository.getOrCreate()
            // Using NotificationsRepository convenience extension through a temporary Noop replacement is not ideal.
            // For v1, we assume scheduling is handled by a dedicated use case from the environment.
        } catch {
            // ignore
        }
    }
}
