import SwiftUI
import SwiftData
import OSLog

extension Notification.Name {
    nonisolated static let googleRefreshTokenUpdated = Notification.Name("GoogleRefreshTokenUpdated")
}

@MainActor
final class GoogleRefreshTokenObserverRegistry {
    private var observer: NSObjectProtocol?
    private var center: NotificationCenter?
    private var onTokenUpdated: (@MainActor (String) async -> Void)?

    func install(
        center: NotificationCenter = .default,
        onTokenUpdated: @escaping @MainActor (String) async -> Void
    ) {
        invalidate()

        self.center = center
        self.onTokenUpdated = onTokenUpdated
        observer = center.addObserver(forName: .googleRefreshTokenUpdated, object: nil, queue: nil) { [weak self] notification in
            guard let newRT = notification.userInfo?["refreshToken"] as? String else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.onTokenUpdated?(newRT)
            }
        }
    }

    func invalidate() {
        if let observer, let center {
            center.removeObserver(observer)
        }
        observer = nil
        self.center = nil
        onTokenUpdated = nil
    }
}

@MainActor
struct AppContainer {
    private enum UserSurfacePolicy: String {
        case suppressed
    }

    private static let refreshTokenObserverRegistry = GoogleRefreshTokenObserverRegistry()
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "DDiary",
        category: "AppContainer"
    )

    let measurementsRepository: any MeasurementsRepository
    let settingsRepository: any SettingsRepository
    let googleIntegrationRepository: any GoogleIntegrationRepository
    let notificationsRepository: any NotificationsRepository
    let analyticsRepository: any AnalyticsRepository
    let googleSheetsClient: any GoogleSheetsClient
    let getTodayOverviewUseCase: GetTodayOverviewUseCase
    let getHistoryUseCase: GetHistoryUseCase
    let updateSchedulesUseCase: UpdateSchedulesUseCase
    let rescheduleGlucoseCycleUseCase: RescheduleGlucoseCycleUseCase
    let notificationsActionUseCase: NotificationsActionUseCase

    let logBPMeasurementUseCase: LogBPMeasurementUseCase
    let logGlucoseMeasurementUseCase: LogGlucoseMeasurementUseCase
    let updateBPMeasurementUseCase: UpdateBPMeasurementUseCase
    let updateGlucoseMeasurementUseCase: UpdateGlucoseMeasurementUseCase
    let exportCSVUseCase: ExportCSVUseCase
    let syncWithGoogleUseCase: SyncWithGoogleUseCase

    init(modelContext: ModelContext) {
        let measurementsRepository = SwiftDataMeasurementsRepository(modelContext: modelContext)
        let settingsRepository = SwiftDataSettingsRepository(modelContext: modelContext)
        let googleIntegrationRepository = SwiftDataGoogleIntegrationRepository(modelContext: modelContext)
        let notificationsRepository = UserNotificationsRepository()
        let analyticsRepository = AmplitudeAnalyticsRepository()
        let googleSheetsClient = LiveGoogleSheetsClient()

        // Configure Google token persistence bridge: token center -> NotificationCenter -> MainActor repo
        LiveGoogleSheetsClientConfig.configureTokenPersistence(onRefreshTokenUpdated: { newRT in
            NotificationCenter.default.post(name: .googleRefreshTokenUpdated, object: nil, userInfo: ["refreshToken": newRT])
        })

        // Use a managed observer that replaces prior registrations to avoid duplicate side effects.
        Self.refreshTokenObserverRegistry.install(onTokenUpdated: { [googleIntegrationRepository] newRT in
            do {
                let integration = try await googleIntegrationRepository.getOrCreate()
                if integration.refreshToken != newRT {
                    integration.refreshToken = newRT
                    try await googleIntegrationRepository.update(integration)
                }
            } catch {
                Self.log(error, operation: "persistGoogleRefreshToken", policy: .suppressed)
            }
        })

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

        let syncWithGoogleUseCase = SyncWithGoogleUseCase(
            googleIntegrationRepository: googleIntegrationRepository,
            measurementsRepository: measurementsRepository,
            analyticsRepository: analyticsRepository,
            googleSheetsClient: googleSheetsClient
        )
        self.syncWithGoogleUseCase = syncWithGoogleUseCase

        self.logBPMeasurementUseCase = LogBPMeasurementUseCase(
            measurementsRepository: measurementsRepository,
            analyticsRepository: analyticsRepository,
            scheduleGoogleSyncIfConnected: { [syncWithGoogleUseCase] in
                syncWithGoogleUseCase.scheduleSyncIfConnected()
            }
        )
        self.logGlucoseMeasurementUseCase = LogGlucoseMeasurementUseCase(
            measurementsRepository: measurementsRepository,
            settingsRepository: settingsRepository,
            analyticsRepository: analyticsRepository,
            scheduleGoogleSyncIfConnected: { [syncWithGoogleUseCase] in
                syncWithGoogleUseCase.scheduleSyncIfConnected()
            }
        )
        self.updateBPMeasurementUseCase = UpdateBPMeasurementUseCase(
            measurementsRepository: measurementsRepository,
            analyticsRepository: analyticsRepository
        )
        self.updateGlucoseMeasurementUseCase = UpdateGlucoseMeasurementUseCase(
            measurementsRepository: measurementsRepository,
            analyticsRepository: analyticsRepository
        )
        self.exportCSVUseCase = ExportCSVUseCase(
            measurementsRepository: measurementsRepository
        )
        self.updateSchedulesUseCase = UpdateSchedulesUseCase(
            settingsRepository: settingsRepository,
            notificationsRepository: notificationsRepository,
            analyticsRepository: analyticsRepository
        )
        self.rescheduleGlucoseCycleUseCase = RescheduleGlucoseCycleUseCase(
            settingsRepository: settingsRepository,
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

    private static func log(_ error: Error, operation: String, policy: UserSurfacePolicy) {
        logger.error(
            "\(operation, privacy: .public) failed. user_surface=\(policy.rawValue, privacy: .public) error=\(String(describing: error), privacy: .public)"
        )
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
