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
    private let cancelPlannedNotification: @MainActor (GlucoseMeasurementType, Date) async -> Void
    private let rescheduleShiftedAfterMealNotification: @MainActor (MealSlot, Date, Date) async -> Void

    public init(
        measurementsRepository: MeasurementsRepository,
        settingsRepository: SettingsRepository,
        analyticsRepository: AnalyticsRepository,
        scheduleGoogleSyncIfConnected: @escaping @MainActor () -> Void = {},
        cancelPlannedNotification: @escaping @MainActor (GlucoseMeasurementType, Date) async -> Void = { _, _ in },
        rescheduleShiftedAfterMealNotification: @escaping @MainActor (MealSlot, Date, Date) async -> Void = { _, _, _ in }
    ) {
        self.measurementsRepository = measurementsRepository
        self.settingsRepository = settingsRepository
        self.analyticsRepository = analyticsRepository
        self.scheduleGoogleSyncIfConnected = scheduleGoogleSyncIfConnected
        self.cancelPlannedNotification = cancelPlannedNotification
        self.rescheduleShiftedAfterMealNotification = rescheduleShiftedAfterMealNotification
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
        comment: String?,
        plannedScheduledDate: Date? = nil
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
        do {
            try await measurementsRepository.insertGlucose(measurement)
        } catch {
            await analyticsRepository.logMeasurementSaveFailed(
                kind: .glucose,
                reason: String(describing: error)
            )
            throw error
        }

        // Start best-effort Google sync immediately when integration is connected.
        scheduleGoogleSyncIfConnected()

        if let plannedScheduledDate {
            await cancelPlannedNotification(measurementType, plannedScheduledDate)
            await rescheduleAfterMealNotificationIfNeeded(
                measurementType: measurementType,
                mealSlot: mealSlot,
                plannedBeforeDate: plannedScheduledDate,
                loggedBeforeDate: measurement.timestamp
            )
        }

        // Fire analytics in the background of this async context.
        await analyticsRepository.logMeasurementLogged(kind: .glucose)
    }

    private func rescheduleAfterMealNotificationIfNeeded(
        measurementType: GlucoseMeasurementType,
        mealSlot: MealSlot,
        plannedBeforeDate: Date,
        loggedBeforeDate: Date
    ) async {
        guard measurementType == .beforeMeal else { return }
        guard mealSlot != .none else { return }
        let calendar = Calendar.current
        guard
            let originalAfterDate = calendar.date(byAdding: .hour, value: 2, to: plannedBeforeDate),
            let shiftedAfterDate = calendar.date(byAdding: .hour, value: 2, to: loggedBeforeDate)
        else {
            return
        }
        await rescheduleShiftedAfterMealNotification(mealSlot, originalAfterDate, shiftedAfterDate)
    }
}
