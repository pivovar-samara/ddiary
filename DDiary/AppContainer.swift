import Foundation
import SwiftUI
import SwiftData

// MARK: - No-op repository implementations for previews
@MainActor struct NoopMeasurementsRepository: MeasurementsRepository {
    func createBPMeasurement(_ measurement: BPMeasurementDTO) async throws -> BPMeasurementDTO { measurement }
    func getBPMeasurement(id: UUID) async throws -> BPMeasurementDTO? { nil }
    func updateBPMeasurement(_ measurement: BPMeasurementDTO) async throws -> BPMeasurementDTO { measurement }
    func deleteBPMeasurement(id: UUID) async throws {}

    func createGlucoseMeasurement(_ measurement: GlucoseMeasurementDTO) async throws -> GlucoseMeasurementDTO { measurement }
    func getGlucoseMeasurement(id: UUID) async throws -> GlucoseMeasurementDTO? { nil }
    func updateGlucoseMeasurement(_ measurement: GlucoseMeasurementDTO) async throws -> GlucoseMeasurementDTO { measurement }
    func deleteGlucoseMeasurement(id: UUID) async throws {}

    func fetchAllBloodPressureMeasurements() async throws -> [BPMeasurementDTO] { [] }
    func fetchAllGlucoseMeasurements() async throws -> [GlucoseMeasurementDTO] { [] }
    func fetchBloodPressureMeasurements(from startDate: Date, to endDate: Date) async throws -> [BPMeasurementDTO] { [] }
    func fetchGlucoseMeasurements(from startDate: Date, to endDate: Date) async throws -> [GlucoseMeasurementDTO] { [] }
}

@MainActor struct NoopRotationScheduleRepository: RotationScheduleRepository {
    func getRotationState() async throws -> GlucoseRotationStateDTO { GlucoseRotationStateDTO() }
    func updateRotationState(_ state: GlucoseRotationStateDTO) async throws -> GlucoseRotationStateDTO { state }
}

@MainActor struct NoopSettingsRepository: SettingsRepository {
    func getOrCreateUserSettings() async throws -> UserSettingsDTO { UserSettingsDTO() }
    func updateUserSettings(_ settings: UserSettingsDTO) async throws -> UserSettingsDTO { settings }
}

// MARK: - UseCase actors
public enum MeasurementValidationError: LocalizedError {
    case invalidBloodPressure
    case invalidGlucose

    public var errorDescription: String? {
        switch self {
        case .invalidBloodPressure:
            return "Blood pressure values must be positive."
        case .invalidGlucose:
            return "Glucose value must be positive."
        }
    }
}

public actor LogBPMeasurementUseCase {
    private let measurements: any MeasurementsRepository
    public init(measurements: any MeasurementsRepository) {
        self.measurements = measurements
    }

    public func execute(_ measurement: BPMeasurementDTO) async throws -> BPMeasurementDTO {
        guard measurement.systolic > 0, measurement.diastolic > 0, measurement.pulse >= 0 else {
            throw MeasurementValidationError.invalidBloodPressure
        }
        return try await measurements.createBPMeasurement(measurement)
    }
}

public actor GetBPHistoryUseCase {
    private let measurements: any MeasurementsRepository
    public init(measurements: any MeasurementsRepository) {
        self.measurements = measurements
    }

    public func execute() async throws -> [BPMeasurementDTO] {
        let items = try await measurements.fetchAllBloodPressureMeasurements()
        return items.sorted { $0.timestamp > $1.timestamp }
    }
}

public actor LogGlucoseMeasurementUseCase {
    private let measurements: any MeasurementsRepository
    public init(measurements: any MeasurementsRepository) {
        self.measurements = measurements
    }

    public func execute(_ measurement: GlucoseMeasurementDTO) async throws -> GlucoseMeasurementDTO {
        guard measurement.value > 0 else { throw MeasurementValidationError.invalidGlucose }
        return try await measurements.createGlucoseMeasurement(measurement)
    }
}

public actor GetGlucoseHistoryUseCase {
    private let measurements: any MeasurementsRepository
    public init(measurements: any MeasurementsRepository) {
        self.measurements = measurements
    }

    public func execute() async throws -> [GlucoseMeasurementDTO] {
        let items = try await measurements.fetchAllGlucoseMeasurements()
        return items.sorted { $0.timestamp > $1.timestamp }
    }
}

// MARK: - AppContainer
@MainActor
public struct AppContainer {
    // SwiftData model container shared across the app
    public let modelContainer: ModelContainer

    // Repositories
    public let measurementsRepository: any MeasurementsRepository
    public let rotationScheduleRepository: any RotationScheduleRepository
    public let settingsRepository: any SettingsRepository

    // Use Cases (actors)
    public let logBPMeasurementUseCase: LogBPMeasurementUseCase
    public let getBPHistoryUseCase: GetBPHistoryUseCase
    public let logGlucoseMeasurementUseCase: LogGlucoseMeasurementUseCase
    public let getGlucoseHistoryUseCase: GetGlucoseHistoryUseCase

    public init(
        modelContainer: ModelContainer,
        measurementsRepository: any MeasurementsRepository,
        rotationScheduleRepository: any RotationScheduleRepository,
        settingsRepository: any SettingsRepository
    ) {
        self.modelContainer = modelContainer
        self.measurementsRepository = measurementsRepository
        self.rotationScheduleRepository = rotationScheduleRepository
        self.settingsRepository = settingsRepository

        // Wire up use cases from repositories
        self.logBPMeasurementUseCase = LogBPMeasurementUseCase(measurements: measurementsRepository)
        self.getBPHistoryUseCase = GetBPHistoryUseCase(measurements: measurementsRepository)
        self.logGlucoseMeasurementUseCase = LogGlucoseMeasurementUseCase(measurements: measurementsRepository)
        self.getGlucoseHistoryUseCase = GetGlucoseHistoryUseCase(measurements: measurementsRepository)
    }

    // Convenience factory for previews or bootstrapping with no-op implementations
    public static func placeholder(using modelContainer: ModelContainer) -> AppContainer {
        let measurements = NoopMeasurementsRepository()
        let rotation = NoopRotationScheduleRepository()
        let settings = NoopSettingsRepository()

        return AppContainer(
            modelContainer: modelContainer,
            measurementsRepository: measurements,
            rotationScheduleRepository: rotation,
            settingsRepository: settings
        )
    }
}

// MARK: - Environment helpers
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
