import Foundation

/// Use case for updating an existing glucose measurement.
/// - Note: MainActor because it mutates SwiftData @Model instances via a MainActor-bound repository.
@MainActor
public final class UpdateGlucoseMeasurementUseCase {
    private let measurementsRepository: any MeasurementsRepository
    private let analyticsRepository: any AnalyticsRepository
    private let scheduleGoogleSyncIfConnected: @MainActor () -> Void

    public init(
        measurementsRepository: any MeasurementsRepository,
        analyticsRepository: any AnalyticsRepository,
        scheduleGoogleSyncIfConnected: @escaping @MainActor () -> Void = {}
    ) {
        self.measurementsRepository = measurementsRepository
        self.analyticsRepository = analyticsRepository
        self.scheduleGoogleSyncIfConnected = scheduleGoogleSyncIfConnected
    }

    public func execute(
        measurement: GlucoseMeasurement,
        value: Double,
        unit: GlucoseUnit,
        measurementType: GlucoseMeasurementType,
        mealSlot: MealSlot,
        comment: String?
    ) async throws {
        measurement.value = value
        measurement.unit = unit
        measurement.measurementType = measurementType
        measurement.mealSlot = mealSlot
        measurement.comment = comment
        measurement.googleSyncStatus = .pending
        measurement.googleLastError = nil
        do {
            try await measurementsRepository.updateGlucose(measurement)
        } catch {
            await analyticsRepository.logMeasurementSaveFailed(
                kind: .glucose,
                reason: String(describing: error)
            )
            throw error
        }
        scheduleGoogleSyncIfConnected()
        // Optional analytics: treat as a measurement interaction
        await analyticsRepository.logMeasurementLogged(kind: .glucose)
    }
}
