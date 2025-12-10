import Foundation

/// Use case for logging a new glucose measurement.
/// - Note: This type is `@MainActor` because it creates SwiftData `@Model` instances
///   and interacts with `@MainActor` repositories.
@MainActor
public final class LogGlucoseMeasurementUseCase {
    private let measurementsRepository: MeasurementsRepository
    private let settingsRepository: SettingsRepository
    private let analyticsRepository: AnalyticsRepository

    public init(
        measurementsRepository: MeasurementsRepository,
        settingsRepository: SettingsRepository,
        analyticsRepository: AnalyticsRepository
    ) {
        self.measurementsRepository = measurementsRepository
        self.settingsRepository = settingsRepository
        self.analyticsRepository = analyticsRepository
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

        // Optionally update cycle mode state. This is a placeholder hook where
        // future logic can adjust daily cycle fields in settings and save them.
        // Example minimal stub (no-op for now):
        // try await updateDailyCycleIfNeeded(afterLogging: measurement, settings: settings)

        // Fire analytics in the background of this async context.
        await analyticsRepository.logMeasurementLogged(kind: .glucose)
    }

    // MARK: - Optional helpers (stubs)

    /// Placeholder for updating daily-cycle-related fields after logging a measurement.
    /// Keep this method on the main actor to mutate settings safely.
    private func updateDailyCycleIfNeeded(
        afterLogging measurement: GlucoseMeasurement,
        settings: UserSettings
    ) async throws {
        // Intentionally left minimal for v1; implement cycle logic later.
        // If you update `settings`, remember to save via `settingsRepository.save(settings)`.
    }
}
