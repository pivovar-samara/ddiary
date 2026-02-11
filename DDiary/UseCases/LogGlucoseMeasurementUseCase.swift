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

        try await updateDailyCycleIfNeeded(afterLogging: measurement, settings: settings)

        // Fire analytics in the background of this async context.
        await analyticsRepository.logMeasurementLogged(kind: .glucose)
    }

    // MARK: - Helpers

    /// Advances daily cycle target only when a before-meal entry is logged for the current target slot.
    private func updateDailyCycleIfNeeded(
        afterLogging measurement: GlucoseMeasurement,
        settings: UserSettings
    ) async throws {
        guard settings.enableDailyCycleMode else { return }
        guard settings.enableBeforeMeal else { return }
        guard measurement.measurementType == .beforeMeal else { return }

        let order = cycleOrder(from: settings)
        guard !order.isEmpty else { return }

        let currentIndex = positiveModulo(settings.currentCycleIndex, order.count)
        guard order[currentIndex] == measurement.mealSlot else { return }

        settings.currentCycleIndex = (currentIndex + 1) % order.count
        try await settingsRepository.save(settings)
    }

    private func cycleOrder(from settings: UserSettings) -> [MealSlot] {
        var order: [MealSlot] = [.breakfast, .lunch, .dinner]
        if settings.bedtimeSlotEnabled {
            // `none` represents bedtime in cycle ordering.
            order.append(.none)
        }
        return order
    }

    private func positiveModulo(_ value: Int, _ modulus: Int) -> Int {
        let remainder = value % modulus
        return remainder >= 0 ? remainder : remainder + modulus
    }
}
