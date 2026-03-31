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
    private static let prettyDataRefreshToken = "pretty-data-refresh-token"

    let isPrettyDataMode: Bool
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

    init(
        modelContext: ModelContext,
        notificationsRepository: any NotificationsRepository = UserNotificationsRepository(),
        analyticsRepository: any AnalyticsRepository = AmplitudeAnalyticsRepository(),
        googleSheetsClient: any GoogleSheetsClient = LiveGoogleSheetsClient(),
        tokenStorage: any TokenStorage = KeychainTokenStorage(),
        configureGoogleTokenPersistence: Bool = true,
        isPrettyDataMode: Bool = false
    ) {
        let measurementsRepository = SwiftDataMeasurementsRepository(modelContext: modelContext)
        let settingsRepository = SwiftDataSettingsRepository(modelContext: modelContext)
        let googleIntegrationRepository = SwiftDataGoogleIntegrationRepository(
            modelContext: modelContext,
            tokenStorage: tokenStorage
        )

        // Configure Google token persistence bridge: token center -> NotificationCenter -> MainActor repo
        if configureGoogleTokenPersistence {
            LiveGoogleSheetsClientConfig.configureTokenPersistence(onRefreshTokenUpdated: { newRT in
                NotificationCenter.default.post(name: .googleRefreshTokenUpdated, object: nil, userInfo: ["refreshToken": newRT])
            })
        } else {
            LiveGoogleSheetsClientConfig.configureTokenPersistence(onRefreshTokenUpdated: nil)
        }

        // Use a managed observer that replaces prior registrations to avoid duplicate side effects.
        Self.refreshTokenObserverRegistry.install(onTokenUpdated: { [googleIntegrationRepository] newRT in
            do {
                let currentToken = try await googleIntegrationRepository.getRefreshToken()
                if currentToken != newRT {
                    try await googleIntegrationRepository.setRefreshToken(newRT)
                }
            } catch {
                Self.log(error, operation: "persistGoogleRefreshToken", policy: .suppressed)
            }
        })

        self.isPrettyDataMode = isPrettyDataMode
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
            },
            cancelPlannedNotification: { [notificationsRepository] scheduledDate in
                await notificationsRepository.cancelPlannedBloodPressureNotification(at: scheduledDate)
            }
        )
        self.logGlucoseMeasurementUseCase = LogGlucoseMeasurementUseCase(
            measurementsRepository: measurementsRepository,
            settingsRepository: settingsRepository,
            analyticsRepository: analyticsRepository,
            scheduleGoogleSyncIfConnected: { [syncWithGoogleUseCase] in
                syncWithGoogleUseCase.scheduleSyncIfConnected()
            },
            cancelPlannedNotification: { [notificationsRepository] measurementType, scheduledDate in
                await notificationsRepository.cancelPlannedGlucoseNotification(
                    measurementType: measurementType,
                    at: scheduledDate
                )
            },
            rescheduleShiftedAfterMealNotification: { [notificationsRepository] mealSlot, originalAfterDate, shiftedAfterDate in
                await notificationsRepository.rescheduleShiftedAfterMeal2hNotification(
                    mealSlot: mealSlot,
                    originalAfterDate: originalAfterDate,
                    shiftedAfterDate: shiftedAfterDate
                )
            }
        )
        self.updateBPMeasurementUseCase = UpdateBPMeasurementUseCase(
            measurementsRepository: measurementsRepository,
            analyticsRepository: analyticsRepository,
            scheduleGoogleSyncIfConnected: { [syncWithGoogleUseCase] in
                syncWithGoogleUseCase.scheduleSyncIfConnected()
            }
        )
        self.updateGlucoseMeasurementUseCase = UpdateGlucoseMeasurementUseCase(
            measurementsRepository: measurementsRepository,
            analyticsRepository: analyticsRepository,
            scheduleGoogleSyncIfConnected: { [syncWithGoogleUseCase] in
                syncWithGoogleUseCase.scheduleSyncIfConnected()
            }
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
            notificationsRepository: notificationsRepository,
            analyticsRepository: analyticsRepository
        )
    }

    init(modelContainer: ModelContainer) {
        self.init(modelContext: ModelContext(modelContainer))
    }

    static func prettyData(modelContainer: ModelContainer) -> AppContainer {
        let tokenStorage = InMemoryTokenStorage()
        try? tokenStorage.write(Self.prettyDataRefreshToken, key: "ddiary.google.oauth.refreshToken")

        return AppContainer(
            modelContext: ModelContext(modelContainer),
            notificationsRepository: SilentNotificationsRepository(),
            analyticsRepository: NoopAnalyticsRepository(),
            googleSheetsClient: DisabledGoogleSheetsClient(),
            tokenStorage: tokenStorage,
            configureGoogleTokenPersistence: false,
            isPrettyDataMode: true
        )
    }
    
    static var preview: AppContainer {
        let modelContainer = try! ModelContainer(
            for: Schema(versionedSchema: DDiarySchemaV1.self),
            migrationPlan: DDiaryMigrationPlan.self,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)]
        )
        try! PrettyDataSeeder.seed(.showcase, into: modelContainer)
        return AppContainer.prettyData(modelContainer: modelContainer)
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
