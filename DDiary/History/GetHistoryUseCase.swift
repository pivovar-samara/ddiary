import Foundation

@MainActor
public final class GetHistoryUseCase {
    private let measurementsRepository: any MeasurementsRepository

    public init(measurementsRepository: any MeasurementsRepository) {
        self.measurementsRepository = measurementsRepository
    }

    /// Fetch history measurements within the inclusive date range.
    /// - Parameters:
    ///   - startDate: Inclusive start.
    ///   - endDate: Inclusive end.
    ///   - includeBP: Whether to include blood pressure measurements.
    ///   - includeGlucose: Whether to include glucose measurements.
    /// - Returns: Tuple of arrays for BP and Glucose.
    public func fetch(
        from startDate: Date,
        to endDate: Date,
        includeBP: Bool,
        includeGlucose: Bool
    ) async throws -> (bp: [BPMeasurement], glucose: [GlucoseMeasurement]) {
        var bp: [BPMeasurement] = []
        var glucose: [GlucoseMeasurement] = []

        if includeBP {
            bp = try await measurementsRepository.bpMeasurements(from: startDate, to: endDate)
        }
        if includeGlucose {
            glucose = try await measurementsRepository.glucoseMeasurements(from: startDate, to: endDate)
        }
        return (bp, glucose)
    }
}
