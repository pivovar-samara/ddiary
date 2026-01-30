import Foundation

/// Use case for updating an existing blood pressure measurement.
/// - Note: MainActor because it mutates SwiftData @Model instances via a MainActor-bound repository.
@MainActor
public final class UpdateBPMeasurementUseCase {
    private let measurementsRepository: any MeasurementsRepository
    private let analyticsRepository: any AnalyticsRepository

    public init(
        measurementsRepository: any MeasurementsRepository,
        analyticsRepository: any AnalyticsRepository
    ) {
        self.measurementsRepository = measurementsRepository
        self.analyticsRepository = analyticsRepository
    }

    public func execute(
        measurement: BPMeasurement,
        systolic: Int,
        diastolic: Int,
        pulse: Int,
        comment: String?
    ) async throws {
        measurement.systolic = systolic
        measurement.diastolic = diastolic
        measurement.pulse = pulse
        measurement.comment = comment
        measurement.googleSyncStatus = .pending
        measurement.googleLastError = nil
        try await measurementsRepository.updateBP(measurement)
        // Optional analytics: treat as a measurement interaction
        await analyticsRepository.logMeasurementLogged(kind: .bloodPressure)
    }
}
