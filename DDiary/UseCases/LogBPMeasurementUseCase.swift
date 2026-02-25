import Foundation

/// Use case for logging a new blood pressure measurement.
/// - Note: This type is `@MainActor` because it creates SwiftData `@Model` instances
///   and interacts with `@MainActor` repositories.
@MainActor
public final class LogBPMeasurementUseCase {
    private let measurementsRepository: MeasurementsRepository
    private let analyticsRepository: AnalyticsRepository
    private let scheduleGoogleSyncIfConnected: @MainActor () -> Void
    private let cancelPlannedNotification: @MainActor (Date) async -> Void

    public init(
        measurementsRepository: MeasurementsRepository,
        analyticsRepository: AnalyticsRepository,
        scheduleGoogleSyncIfConnected: @escaping @MainActor () -> Void = {},
        cancelPlannedNotification: @escaping @MainActor (Date) async -> Void = { _ in }
    ) {
        self.measurementsRepository = measurementsRepository
        self.analyticsRepository = analyticsRepository
        self.scheduleGoogleSyncIfConnected = scheduleGoogleSyncIfConnected
        self.cancelPlannedNotification = cancelPlannedNotification
    }

    /// Create and persist a new `BPMeasurement` and log analytics.
    /// - Parameters:
    ///   - systolic: Systolic value.
    ///   - diastolic: Diastolic value.
    ///   - pulse: Pulse value.
    ///   - comment: Optional comment.
    public func execute(
        systolic: Int,
        diastolic: Int,
        pulse: Int,
        comment: String?,
        plannedScheduledDate: Date? = nil
    ) async throws {
        // Build the measurement with a current timestamp and mark Google sync as pending.
        let measurement = BPMeasurement(
            id: UUID(),
            timestamp: Date(),
            systolic: systolic,
            diastolic: diastolic,
            pulse: pulse,
            comment: comment,
            isLinkedToSchedule: plannedScheduledDate != nil,
            googleSyncStatus: .pending,
            googleLastError: nil,
            googleLastSyncAt: nil
        )

        // Persist via the repository (MainActor-bound).
        do {
            try await measurementsRepository.insertBP(measurement)
        } catch {
            await analyticsRepository.logMeasurementSaveFailed(
                kind: .bloodPressure,
                reason: String(describing: error)
            )
            throw error
        }

        // Start best-effort Google sync immediately when integration is connected.
        scheduleGoogleSyncIfConnected()

        if let plannedScheduledDate {
            await cancelPlannedNotification(plannedScheduledDate)
        }

        // Fire analytics in the background of this async context.
        await analyticsRepository.logMeasurementLogged(kind: .bloodPressure)
    }
}
