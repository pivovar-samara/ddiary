//
//  CompositeAnalyticsRepository.swift
//  DDiary
//

import Foundation

/// Maps the domain-level `AnalyticsRepository` calls onto `AnalyticsEventFactory` events
/// and fans them out to every configured provider.
nonisolated final class CompositeAnalyticsRepository: AnalyticsRepository, @unchecked Sendable {
    private let sinks: [any AnalyticsEventSink]

    init(sinks: [any AnalyticsEventSink]) {
        self.sinks = sinks
    }

    private func emit(_ event: AnalyticsEvent) {
        for sink in sinks {
            sink.send(event)
        }
    }

    // MARK: - AnalyticsRepository

    func logAppOpen() async {
        emit(AnalyticsEventFactory.appOpen())
    }

    func logMeasurementLogged(kind: AnalyticsMeasurementKind) async {
        emit(AnalyticsEventFactory.measurementLogged(kind: kind))
    }

    func logMeasurementSaveFailed(kind: AnalyticsMeasurementKind, reason: String?) async {
        emit(AnalyticsEventFactory.measurementSaveFailed(kind: kind, reason: reason))
    }

    func logScheduleUpdated(kind: AnalyticsScheduleKind) async {
        emit(AnalyticsEventFactory.scheduleUpdated(kind: kind))
    }

    func logScheduleUpdateFailed(kind: AnalyticsScheduleKind, reason: String?) async {
        emit(AnalyticsEventFactory.scheduleUpdateFailed(kind: kind, reason: reason))
    }

    func logExportCSV() async {
        emit(AnalyticsEventFactory.exportCSV())
    }

    func logGoogleSyncSuccess() async {
        emit(AnalyticsEventFactory.gsheetsSyncSuccess())
    }

    func logGoogleSyncFailure(reason: String?) async {
        emit(AnalyticsEventFactory.gsheetsSyncFailure(reason: reason))
    }

    func logGoogleSyncFinished(successCount: Int, failureCount: Int) async {
        emit(AnalyticsEventFactory.gsheetsSyncFinished(successCount: successCount, failureCount: failureCount))
    }

    func logGoogleEnabled() async {
        emit(AnalyticsEventFactory.gsheetsEnabled())
    }

    func logGoogleDisabled() async {
        emit(AnalyticsEventFactory.gsheetsDisabled())
    }
}
