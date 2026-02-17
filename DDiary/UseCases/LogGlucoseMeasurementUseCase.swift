import Foundation

/// Use case for logging a new glucose measurement.
/// - Note: This type is `@MainActor` because it creates SwiftData `@Model` instances
///   and interacts with `@MainActor` repositories.
@MainActor
public final class LogGlucoseMeasurementUseCase {
    private let measurementsRepository: MeasurementsRepository
    private let settingsRepository: SettingsRepository
    private let analyticsRepository: AnalyticsRepository
    private let scheduleGoogleSyncIfConnected: @MainActor () -> Void

    public init(
        measurementsRepository: MeasurementsRepository,
        settingsRepository: SettingsRepository,
        analyticsRepository: AnalyticsRepository,
        scheduleGoogleSyncIfConnected: @escaping @MainActor () -> Void = {}
    ) {
        self.measurementsRepository = measurementsRepository
        self.settingsRepository = settingsRepository
        self.analyticsRepository = analyticsRepository
        self.scheduleGoogleSyncIfConnected = scheduleGoogleSyncIfConnected
    }

    /// Create and persist a new `GlucoseMeasurement` and log analytics.
    /// - Parameters:
    ///   - value: Glucose value.
    ///   - measurementType: Context relative to meals (before/after/bedtime).
    ///   - mealSlot: Breakfast/Lunch/Dinner/None.
    ///   - comment: Optional comment.
    public func execute(
        value: Double,
        measurementType: GlucoseMeasurementType,
        mealSlot: MealSlot,
        comment: String?
    ) async throws {
        // Read user settings to determine the preferred glucose unit.
        let settings = try await settingsRepository.getOrCreate()
        let unit = settings.glucoseUnit

        // Build the measurement with a current timestamp and mark Google sync as pending.
        let measurement = GlucoseMeasurement(
            id: UUID(),
            timestamp: Date(),
            value: value,
            unit: unit,
            measurementType: measurementType,
            mealSlot: mealSlot,
            comment: comment,
            googleSyncStatus: .pending,
            googleLastError: nil,
            googleLastSyncAt: nil
        )

        // Persist via the repository (MainActor-bound).
        try await measurementsRepository.insertGlucose(measurement)

        // Start best-effort Google sync immediately when integration is connected.
        scheduleGoogleSyncIfConnected()

        // Fire analytics in the background of this async context.
        await analyticsRepository.logMeasurementLogged(kind: .glucose)
    }
}
