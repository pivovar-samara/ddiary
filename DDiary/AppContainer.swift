import Foundation
import SwiftUI
import SwiftData

@MainActor
final class SyncWithGoogleUseCase {
    private let googleIntegrationRepository: any GoogleIntegrationRepository
    private let measurementsRepository: any MeasurementsRepository
    private let analyticsRepository: any AnalyticsRepository
    private let googleSheetsClient: any GoogleSheetsClient

    init(
        googleIntegrationRepository: any GoogleIntegrationRepository,
        measurementsRepository: any MeasurementsRepository,
        analyticsRepository: any AnalyticsRepository,
        googleSheetsClient: any GoogleSheetsClient
    ) {
        self.googleIntegrationRepository = googleIntegrationRepository
        self.measurementsRepository = measurementsRepository
        self.analyticsRepository = analyticsRepository
        self.googleSheetsClient = googleSheetsClient
    }

    /// Push pending/failed measurements to Google Sheets and update their sync status.
    func execute() async {
        do {
            let integration = try await googleIntegrationRepository.getOrCreate()
            guard
                integration.isEnabled,
                let spreadsheetId = integration.spreadsheetId,
                let refreshToken = integration.refreshToken
            else {
                await analyticsRepository.logGoogleSyncFailure(reason: "Integration disabled or missing credentials")
                return
            }

            let credentials = GoogleSheetsCredentials(
                spreadsheetId: spreadsheetId,
                refreshToken: refreshToken,
                googleUserId: integration.googleUserId
            )

            // Fetch pending/failed items
            let pendingBP = try await measurementsRepository.pendingOrFailedBPSync()
            let pendingGlucose = try await measurementsRepository.pendingOrFailedGlucoseSync()

            // Sync BP
            for m in pendingBP.sorted(by: { $0.timestamp < $1.timestamp }) {
                do {
                    let row = GoogleSheetsBPRow(
                        id: m.id,
                        timestamp: m.timestamp,
                        systolic: m.systolic,
                        diastolic: m.diastolic,
                        pulse: m.pulse,
                        comment: m.comment
                    )
                    try await googleSheetsClient.appendBloodPressureRow(row, credentials: credentials)
                    m.googleSyncStatus = .success
                    m.googleLastError = nil
                    m.googleLastSyncAt = Date()
                    try await measurementsRepository.updateBP(m)
                    await analyticsRepository.logGoogleSyncSuccess()
                } catch {
                    m.googleSyncStatus = .failed
                    m.googleLastError = String(describing: error)
                    m.googleLastSyncAt = Date()
                    try? await measurementsRepository.updateBP(m)
                    await analyticsRepository.logGoogleSyncFailure(reason: m.googleLastError)
                }
            }

            // Sync Glucose
            for m in pendingGlucose.sorted(by: { $0.timestamp < $1.timestamp }) {
                do {
                    let row = GoogleSheetsGlucoseRow(
                        id: m.id,
                        timestamp: m.timestamp,
                        value: m.value,
                        unit: m.unit,
                        measurementType: m.measurementType,
                        mealSlot: m.mealSlot,
                        comment: m.comment
                    )
                    try await googleSheetsClient.appendGlucoseRow(row, credentials: credentials)
                    m.googleSyncStatus = .success
                    m.googleLastError = nil
                    m.googleLastSyncAt = Date()
                    try await measurementsRepository.updateGlucose(m)
                    await analyticsRepository.logGoogleSyncSuccess()
                } catch {
                    m.googleSyncStatus = .failed
                    m.googleLastError = String(describing: error)
                    m.googleLastSyncAt = Date()
                    try? await measurementsRepository.updateGlucose(m)
                    await analyticsRepository.logGoogleSyncFailure(reason: m.googleLastError)
                }
            }
        } catch {
            // Repository-level failure: surface as analytics failure; individual records remain unchanged.
            await analyticsRepository.logGoogleSyncFailure(reason: String(describing: error))
        }
    }
}

@MainActor
struct AppContainer {
    let measurementsRepository: any MeasurementsRepository
    let settingsRepository: any SettingsRepository
    let googleIntegrationRepository: any GoogleIntegrationRepository
    let notificationsRepository: any NotificationsRepository
    let analyticsRepository: any AnalyticsRepository
    let googleSheetsClient: any GoogleSheetsClient
    let getTodayOverviewUseCase: GetTodayOverviewUseCase
    let getHistoryUseCase: GetHistoryUseCase

    let logBPMeasurementUseCase: LogBPMeasurementUseCase
    let logGlucoseMeasurementUseCase: LogGlucoseMeasurementUseCase
    let exportCSVUseCase: ExportCSVUseCase
    let syncWithGoogleUseCase: SyncWithGoogleUseCase

    init(modelContext: ModelContext) {
        let measurementsRepository = SwiftDataMeasurementsRepository(modelContext: modelContext)
        let settingsRepository = SwiftDataSettingsRepository(modelContext: modelContext)
        let googleIntegrationRepository = SwiftDataGoogleIntegrationRepository(modelContext: modelContext)
        let notificationsRepository = UserNotificationsRepository()
        let analyticsRepository = AmplitudeAnalyticsRepository()
        let googleSheetsClient = NoopGoogleSheetsClient()
        self.measurementsRepository = measurementsRepository
        self.settingsRepository = settingsRepository
        self.googleIntegrationRepository = googleIntegrationRepository
        self.notificationsRepository = notificationsRepository
        self.analyticsRepository = analyticsRepository
        self.googleSheetsClient = googleSheetsClient

        self.getTodayOverviewUseCase = GetTodayOverviewUseCase(
            measurementsRepository: measurementsRepository,
            settingsRepository: settingsRepository
        )
        self.getHistoryUseCase = GetHistoryUseCase(
            measurementsRepository: measurementsRepository
        )

        self.logBPMeasurementUseCase = LogBPMeasurementUseCase(
            measurementsRepository: measurementsRepository,
            analyticsRepository: analyticsRepository
        )
        self.logGlucoseMeasurementUseCase = LogGlucoseMeasurementUseCase(
            measurementsRepository: measurementsRepository,
            settingsRepository: settingsRepository,
            analyticsRepository: analyticsRepository
        )
        self.exportCSVUseCase = ExportCSVUseCase(
            measurementsRepository: measurementsRepository
        )
        self.syncWithGoogleUseCase = SyncWithGoogleUseCase(
            googleIntegrationRepository: googleIntegrationRepository,
            measurementsRepository: measurementsRepository,
            analyticsRepository: analyticsRepository,
            googleSheetsClient: googleSheetsClient
        )
    }

    init(modelContainer: ModelContainer) {
        self.init(modelContext: ModelContext(modelContainer))
    }
    
    static var preview: AppContainer {
        let modelContainer = try! ModelContainer(
            for: Schema([
                BPMeasurement.self,
                GlucoseMeasurement.self,
                UserSettings.self,
                GoogleIntegration.self,
            ]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return AppContainer(modelContainer: modelContainer)
    }
}

private struct AppContainerKey: EnvironmentKey {
    static let defaultValue: AppContainer = .preview
}

extension EnvironmentValues {
    var appContainer: AppContainer {
        get { self[AppContainerKey.self] }
        set { self[AppContainerKey.self] = newValue }
    }
}

extension View {
    func appContainer(_ container: AppContainer) -> some View {
        environment(\.appContainer, container)
    }
}
