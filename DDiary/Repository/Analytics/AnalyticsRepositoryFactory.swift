//
//  AnalyticsRepositoryFactory.swift
//  DDiary
//

import Foundation
import OSLog

/// Builds the production analytics repository: one shared event mapping, one sink per provider.
@MainActor
enum AnalyticsRepositoryFactory {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "DDiary",
        category: "AnalyticsRepositoryFactory"
    )

    static func make(environment: AnalyticsEnvironment) -> any AnalyticsRepository {
        guard environment.collectionEnabled else {
            return NoopAnalyticsRepository()
        }

        var sinks: [any AnalyticsEventSink] = []

        if let amplitude = AmplitudeAnalyticsEventSink(apiKey: AnalyticsRuntimeConfig.amplitudeAPIKey) {
            sinks.append(amplitude)
        } else {
            logger.error("Amplitude disabled: AMPLITUDE_API_KEY is empty")
        }

        if FirebaseBootstrap.isConfigured {
            sinks.append(FirebaseAnalyticsEventSink())
        } else {
            logger.error("Firebase Analytics disabled: FirebaseApp was not configured")
        }

        return CompositeAnalyticsRepository(sinks: sinks)
    }
}
