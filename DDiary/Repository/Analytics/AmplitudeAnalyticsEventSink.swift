//
//  AmplitudeAnalyticsEventSink.swift
//  DDiary
//

import Foundation
import AmplitudeSwift

nonisolated enum AnalyticsRuntimeConfig {
    static var amplitudeAPIKey: String {
        Bundle.main.object(forInfoDictionaryKey: "AMPLITUDE_API_KEY") as? String ?? ""
    }
}

/// Amplitude provider.
///
/// `enableCoppaControl` is the main privacy lever here: it suppresses `idfa`, `idfv`, `city`
/// and `ip_address` on every event. Country still arrives, derived from the device locale
/// rather than from the IP address, so nothing useful is lost.
public nonisolated final class AmplitudeAnalyticsEventSink: AnalyticsEventSink, @unchecked Sendable {
    private let amplitude: Amplitude

    /// Returns `nil` when the API key is absent so callers can simply omit the sink.
    public init?(apiKey: String) {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let config = Configuration(apiKey: trimmed, autocapture: [.sessions, .appLifecycles])
        config.enableCoppaControl = true
        config.trackingOptions = TrackingOptions()
            .disableTrackDMA()
            .disableTrackRegion()
            .disableTrackCarrier()

        amplitude = Amplitude(configuration: config)
    }

    public func send(_ event: AnalyticsEvent) {
        amplitude.track(eventType: event.name, eventProperties: event.objectProperties)
    }
}
