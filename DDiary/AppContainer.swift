import SwiftUI
import SwiftData

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
    let updateSchedulesUseCase: UpdateSchedulesUseCase
    let notificationsActionUseCase: NotificationsActionUseCase

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
        self.updateSchedulesUseCase = UpdateSchedulesUseCase(
            settingsRepository: settingsRepository,
            notificationsRepository: notificationsRepository,
            analyticsRepository: analyticsRepository
        )
        self.notificationsActionUseCase = NotificationsActionUseCase(
            settingsRepository: settingsRepository,
            notificationsRepository: notificationsRepository,
            analyticsRepository: analyticsRepository
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

