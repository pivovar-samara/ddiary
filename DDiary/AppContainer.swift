import Foundation
import SwiftUI
import SwiftData

@MainActor protocol MeasurementsRepository: AnyObject {}
@MainActor protocol SettingsRepository: AnyObject {}
@MainActor protocol GoogleIntegrationRepository: AnyObject {}
protocol NotificationsRepository: Sendable {}
protocol AnalyticsRepository: Sendable {}

@MainActor
final class SwiftDataMeasurementsRepository: MeasurementsRepository {
    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }
    private let modelContainer: ModelContainer
}

@MainActor
final class SwiftDataSettingsRepository: SettingsRepository {
    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }
    private let modelContainer: ModelContainer
}

@MainActor
final class SwiftDataGoogleIntegrationRepository: GoogleIntegrationRepository {
    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }
    private let modelContainer: ModelContainer
}

struct UserNotificationsRepository: NotificationsRepository {
    init() {}
}

struct NoopAnalyticsRepository: AnalyticsRepository {
    init() {}
}

@MainActor
final class LogBPMeasurementUseCase {
    private let measurementsRepository: any MeasurementsRepository
    private let analyticsRepository: any AnalyticsRepository
    
    init(
        measurementsRepository: any MeasurementsRepository,
        analyticsRepository: any AnalyticsRepository
    ) {
        self.measurementsRepository = measurementsRepository
        self.analyticsRepository = analyticsRepository
    }
}

@MainActor
final class LogGlucoseMeasurementUseCase {
    private let measurementsRepository: any MeasurementsRepository
    private let analyticsRepository: any AnalyticsRepository
    
    init(
        measurementsRepository: any MeasurementsRepository,
        analyticsRepository: any AnalyticsRepository
    ) {
        self.measurementsRepository = measurementsRepository
        self.analyticsRepository = analyticsRepository
    }
}

@MainActor
final class ExportCSVUseCase {
    private let measurementsRepository: any MeasurementsRepository
    private let settingsRepository: any SettingsRepository
    
    init(
        measurementsRepository: any MeasurementsRepository,
        settingsRepository: any SettingsRepository
    ) {
        self.measurementsRepository = measurementsRepository
        self.settingsRepository = settingsRepository
    }
}

@MainActor
final class SyncWithGoogleUseCase {
    private let googleIntegrationRepository: any GoogleIntegrationRepository
    private let measurementsRepository: any MeasurementsRepository
    private let analyticsRepository: any AnalyticsRepository
    private let notificationsRepository: any NotificationsRepository
    init(
        googleIntegrationRepository: any GoogleIntegrationRepository,
        measurementsRepository: any MeasurementsRepository,
        analyticsRepository: any AnalyticsRepository,
        notificationsRepository: any NotificationsRepository
      ) {
        self.googleIntegrationRepository = googleIntegrationRepository
        self.measurementsRepository = measurementsRepository
        self.analyticsRepository = analyticsRepository
        self.notificationsRepository = notificationsRepository
    }
}

@MainActor
struct AppContainer {
    let measurementsRepository: any MeasurementsRepository
    let settingsRepository: any SettingsRepository
    let googleIntegrationRepository: any GoogleIntegrationRepository
    let notificationsRepository: any NotificationsRepository
    let analyticsRepository: any AnalyticsRepository

    let logBPMeasurementUseCase: LogBPMeasurementUseCase
    let logGlucoseMeasurementUseCase: LogGlucoseMeasurementUseCase
    let exportCSVUseCase: ExportCSVUseCase
    let syncWithGoogleUseCase: SyncWithGoogleUseCase

    init(modelContainer: ModelContainer) {
        let measurementsRepository = SwiftDataMeasurementsRepository(modelContainer: modelContainer)
        let settingsRepository = SwiftDataSettingsRepository(modelContainer: modelContainer)
        let googleIntegrationRepository = SwiftDataGoogleIntegrationRepository(modelContainer: modelContainer)
        let notificationsRepository = UserNotificationsRepository()
        let analyticsRepository = NoopAnalyticsRepository()
        self.measurementsRepository = measurementsRepository
        self.settingsRepository = settingsRepository
        self.googleIntegrationRepository = googleIntegrationRepository
        self.notificationsRepository = notificationsRepository
        self.analyticsRepository = analyticsRepository

        self.logBPMeasurementUseCase = LogBPMeasurementUseCase(
            measurementsRepository: measurementsRepository,
            analyticsRepository: analyticsRepository
        )
        self.logGlucoseMeasurementUseCase = LogGlucoseMeasurementUseCase(
            measurementsRepository: measurementsRepository,
            analyticsRepository: analyticsRepository
        )
        self.exportCSVUseCase = ExportCSVUseCase(
            measurementsRepository: measurementsRepository,
            settingsRepository: settingsRepository
        )
        self.syncWithGoogleUseCase = SyncWithGoogleUseCase(
            googleIntegrationRepository: googleIntegrationRepository,
            measurementsRepository: measurementsRepository,
            analyticsRepository: analyticsRepository,
            notificationsRepository: notificationsRepository
        )
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
