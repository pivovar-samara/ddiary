import Foundation
import SwiftUI
import SwiftData

@MainActor struct NoopMeasurementsRepository: MeasurementsRepository {
    let modelContainer: ModelContainer
    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    // MARK: - BP CRUD
    func createBPMeasurement(_ measurement: BPMeasurement) async throws -> BPMeasurement { measurement }
    func getBPMeasurement(id: UUID) async throws -> BPMeasurement? { nil }
    func updateBPMeasurement(_ measurement: BPMeasurement) async throws -> BPMeasurement { measurement }
    func deleteBPMeasurement(id: UUID) async throws {}

    // MARK: - Glucose CRUD
    func createGlucoseMeasurement(_ measurement: GlucoseMeasurement) async throws -> GlucoseMeasurement { measurement }
    func getGlucoseMeasurement(id: UUID) async throws -> GlucoseMeasurement? { nil }
    func updateGlucoseMeasurement(_ measurement: GlucoseMeasurement) async throws -> GlucoseMeasurement { measurement }
    func deleteGlucoseMeasurement(id: UUID) async throws {}

    // MARK: - Queries
    func fetchAllBloodPressureMeasurements() async throws -> [BPMeasurement] { [] }
    func fetchAllGlucoseMeasurements() async throws -> [GlucoseMeasurement] { [] }
    func fetchBloodPressureMeasurements(from startDate: Date, to endDate: Date) async throws -> [BPMeasurement] { [] }
    func fetchGlucoseMeasurements(from startDate: Date, to endDate: Date) async throws -> [GlucoseMeasurement] { [] }

    // MARK: - Google Sync
    func fetchBloodPressureMeasurementsNeedingGoogleSync() async throws -> [BPMeasurement] { [] }
    func fetchGlucoseMeasurementsNeedingGoogleSync() async throws -> [GlucoseMeasurement] { [] }
}

@MainActor struct NoopSettingsRepository: SettingsRepository {
    init() {}
    func getOrCreateUserSettings() async throws -> UserSettings { UserSettings() }
    func updateUserSettings(_ settings: UserSettings) async throws -> UserSettings { settings }
}

@MainActor struct NoopGoogleIntegrationRepository: GoogleIntegrationRepository {
    init() {}
    func getOrCreateGoogleIntegration() async throws -> GoogleIntegration { GoogleIntegration() }
    func updateGoogleIntegration(_ integration: GoogleIntegration) async throws -> GoogleIntegration { integration }
    func clearTokensOnLogout() async throws {}
}

struct NoopNotificationsRepository: NotificationsRepository {
    init() {}
    func requestAuthorization() async throws -> Bool { true }
    func scheduleBloodPressureNotifications(at times: [DateComponents], replaceExisting: Bool) async throws {}
    func scheduleGlucoseNotifications(_ schedule: [GlucoseSlot: [DateComponents]], replaceExisting: Bool) async throws {}
    func cancelAllScheduledNotifications() async throws {}
    func cancelBloodPressureNotifications() async throws {}
    func cancelGlucoseNotifications(slots: Set<GlucoseSlot>?) async throws {}
    func rescheduleBloodPressureNotifications(at times: [DateComponents]) async throws {}
    func rescheduleGlucoseNotifications(_ schedule: [GlucoseSlot: [DateComponents]]) async throws {}
    func snoozeNotification(with identifier: String, by minutes: Int) async throws {}
    func skipNotification(with identifier: String) async throws {}
    func moveNotification(with identifier: String, to date: Date) async throws {}
}

struct NoopAnalyticsRepository: AnalyticsRepository {
    init() {}
    func logAppOpen() async {}
    func logMeasurementLogged(type: MeasurementType) async {}
    func logScheduleUpdated(for type: MeasurementType) async {}
    func logExportCSV() async {}
    func logGoogleSyncSuccess(count: Int?) async {}
    func logGoogleSyncFailure(errorDescription: String?) async {}
    func logGoogleEnabled() async {}
    func logGoogleDisabled() async {}
}

public actor LogBPMeasurementUseCase {
    private let measurements: any MeasurementsRepository
    public init(measurements: any MeasurementsRepository) {
        self.measurements = measurements
    }
}

public actor LogGlucoseMeasurementUseCase {
    private let measurements: any MeasurementsRepository
    public init(measurements: any MeasurementsRepository) {
        self.measurements = measurements
    }
}

public actor ExportCSVUseCase {
    private let measurements: any MeasurementsRepository
    private let settings: any SettingsRepository
    public init(measurements: any MeasurementsRepository, settings: any SettingsRepository) {
        self.measurements = measurements
        self.settings = settings
    }
}

public actor SyncWithGoogleUseCase {
    private let google: any GoogleIntegrationRepository
    private let measurements: any MeasurementsRepository
    public init(google: any GoogleIntegrationRepository, measurements: any MeasurementsRepository) {
        self.google = google
        self.measurements = measurements
    }
}

public struct AppContainer {
    // SwiftData model container shared across the app
    public let modelContainer: ModelContainer

    // Repositories
    public let measurementsRepository: any MeasurementsRepository
    public let settingsRepository: any SettingsRepository
    public let googleIntegrationRepository: any GoogleIntegrationRepository
    public let notificationsRepository: any NotificationsRepository
    public let analyticsRepository: any AnalyticsRepository

    // Use Cases (actors)
    public let logBPMeasurementUseCase: LogBPMeasurementUseCase
    public let logGlucoseMeasurementUseCase: LogGlucoseMeasurementUseCase
    public let exportCSVUseCase: ExportCSVUseCase
    public let syncWithGoogleUseCase: SyncWithGoogleUseCase

    public init(
        modelContainer: ModelContainer,
        measurementsRepository: any MeasurementsRepository,
        settingsRepository: any SettingsRepository,
        googleIntegrationRepository: any GoogleIntegrationRepository,
        notificationsRepository: any NotificationsRepository,
        analyticsRepository: any AnalyticsRepository
    ) {
        self.modelContainer = modelContainer
        self.measurementsRepository = measurementsRepository
        self.settingsRepository = settingsRepository
        self.googleIntegrationRepository = googleIntegrationRepository
        self.notificationsRepository = notificationsRepository
        self.analyticsRepository = analyticsRepository

        // Wire up use cases from repositories
        self.logBPMeasurementUseCase = LogBPMeasurementUseCase(measurements: measurementsRepository)
        self.logGlucoseMeasurementUseCase = LogGlucoseMeasurementUseCase(measurements: measurementsRepository)
        self.exportCSVUseCase = ExportCSVUseCase(
            measurements: measurementsRepository,
            settings: settingsRepository
        )
        self.syncWithGoogleUseCase = SyncWithGoogleUseCase(
            google: googleIntegrationRepository,
            measurements: measurementsRepository
        )
    }

    // Convenience factory for previews or bootstrapping with no-op implementations
    public static func placeholder(using modelContainer: ModelContainer) -> AppContainer {
        let measurements = NoopMeasurementsRepository(modelContainer: modelContainer)
        let settings = NoopSettingsRepository()
        let google = NoopGoogleIntegrationRepository()
        let notifications = NoopNotificationsRepository()
        let analytics = NoopAnalyticsRepository()

        return AppContainer(
            modelContainer: modelContainer,
            measurementsRepository: measurements,
            settingsRepository: settings,
            googleIntegrationRepository: google,
            notificationsRepository: notifications,
            analyticsRepository: analytics
        )
    }
}

private struct AppContainerEnvironmentKey: EnvironmentKey {
    static let defaultValue: AppContainer? = nil
}

extension EnvironmentValues {
    public var appContainer: AppContainer? {
        get { self[AppContainerEnvironmentKey.self] }
        set { self[AppContainerEnvironmentKey.self] = newValue }
    }
}

extension View {
    // Convenience for injecting the app container into the view hierarchy
    public func appContainer(_ container: AppContainer) -> some View {
        environment(\.appContainer, container)
    }
}

private struct AppContainerInjector: ViewModifier {
    @Environment(\.modelContext) private var modelContext
    func body(content: Content) -> some View {
        content.environment(\.appContainer, AppContainer.placeholder(using: modelContext.container))
    }
}

extension View {
    /// Injects a placeholder AppContainer built from the environment's SwiftData ModelContainer.
    public func injectPlaceholderAppContainer() -> some View {
        modifier(AppContainerInjector())
    }
}
