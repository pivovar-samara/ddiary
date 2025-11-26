//
//  AmplitudeAnalyticsRepository.swift
//  DDiary
//
//  Created by Assistant on 26.11.25.
//

import Foundation

/// Simple protocol to abstract an analytics client (so we can swap Amplitude or a mock later).
public protocol AnalyticsClient {
    func logEvent(_ name: String, properties: [String: Any]?) async
}

/// Concrete `AnalyticsRepository` that would send events to Amplitude (or any injected client).
///
/// NOTE: This is a stubbed implementation. No real Amplitude SDK calls are made.
/// Where indicated, you can integrate the official Amplitude SDK.
public final class AmplitudeAnalyticsRepository: AnalyticsRepository {
    private let client: AnalyticsClient

    public init(client: AnalyticsClient) {
        self.client = client
    }

    public func logAppOpen() async {
        // TODO: Replace with Amplitude SDK call, e.g., Amplitude.instance().logEvent("app_open")
        await client.logEvent("app_open", properties: nil)
    }

    public func logMeasurementLogged(type: MeasurementType) async {
        await client.logEvent("measurement_logged", properties: ["type": type.rawValue])
    }

    public func logScheduleUpdated(for type: MeasurementType) async {
        await client.logEvent("schedule_updated", properties: ["type": type.rawValue])
    }

    public func logExportCSV() async {
        await client.logEvent("export_csv", properties: nil)
    }

    public func logGoogleSyncSuccess(count: Int?) async {
        var props: [String: Any] = [:]
        if let count { props["count"] = count }
        await client.logEvent("google_sync_success", properties: props)
    }

    public func logGoogleSyncFailure(errorDescription: String?) async {
        var props: [String: Any] = [:]
        if let errorDescription { props["error"] = errorDescription }
        await client.logEvent("google_sync_failure", properties: props)
    }

    public func logGoogleEnabled() async {
        await client.logEvent("google_enabled", properties: nil)
    }

    public func logGoogleDisabled() async {
        await client.logEvent("google_disabled", properties: nil)
    }
}

/// A no-op client you can use in development or testing.
public struct NoopAnalyticsClient: AnalyticsClient {
    public init() {}
    public func logEvent(_ name: String, properties: [String : Any]?) async {
        // Intentionally no-op. You could print to console here if desired.
    }
}
