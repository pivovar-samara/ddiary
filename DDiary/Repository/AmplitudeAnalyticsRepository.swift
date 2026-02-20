import Foundation
import OSLog
import AmplitudeSwift

private enum AnalyticsRuntimeConfig {
    static var amplitudeAPIKey: String {
        Bundle.main.object(forInfoDictionaryKey: "AMPLITUDE_API_KEY") as? String ?? ""
    }
}

public protocol AmplitudeClient: Sendable {
    func log(event: String, properties: [String: Any]?)
}

public struct ConsoleAmplitudeClient: AmplitudeClient {
    public init() {}

    public func log(event: String, properties: [String: Any]?) {
        if let properties {
            print("[Amplitude] \(event) props=\(properties)")
        } else {
            print("[Amplitude] \(event)")
        }
    }
}

public struct NoopAmplitudeClient: AmplitudeClient {
    public init() {}

    public func log(event _: String, properties _: [String: Any]?) {}
}

public final class LiveAmplitudeClient: AmplitudeClient, @unchecked Sendable {
    private let amplitude: Amplitude

    public init(apiKey: String) {
        let config = Configuration(apiKey: apiKey, autocapture: [.sessions, .appLifecycles])

        config.enableCoppaControl = true
        let options = TrackingOptions()
            .disableTrackDMA()
            .disableTrackRegion()
            .disableTrackCarrier()
        config.trackingOptions = options

        amplitude = Amplitude(configuration: config)
    }

    public func log(event: String, properties: [String: Any]?) {
        amplitude.track(eventType: event, eventProperties: properties)
    }
}

final class AmplitudeAnalyticsRepository: AnalyticsRepository, @unchecked Sendable {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "DDiary",
        category: "AmplitudeAnalyticsRepository"
    )

    private let client: any AmplitudeClient

    init(
        client: (any AmplitudeClient)? = nil,
        apiKey: String = AnalyticsRuntimeConfig.amplitudeAPIKey
    ) {
        if let client {
            self.client = client
            return
        }

        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedKey.isEmpty {
            Self.logger.error("Amplitude disabled: AMPLITUDE_API_KEY is empty")
            self.client = NoopAmplitudeClient()
            return
        }

        self.client = LiveAmplitudeClient(apiKey: trimmedKey)
    }

    // MARK: - AnalyticsRepository
    func logAppOpen() async {
        client.log(event: "app_open", properties: nil)
    }

    func logMeasurementLogged(kind: AnalyticsMeasurementKind) async {
        client.log(event: "measurement_logged", properties: ["kind": measurementKindString(kind)])
    }

    func logMeasurementSaveFailed(kind: AnalyticsMeasurementKind, reason: String?) async {
        client.log(
            event: "measurement_save_failed",
            properties: [
                "kind": measurementKindString(kind),
                "reason": normalizeReason(reason) ?? "unknown",
            ]
        )
    }

    func logScheduleUpdated(kind: AnalyticsScheduleKind) async {
        client.log(event: "schedule_updated", properties: ["kind": scheduleKindString(kind)])
    }

    func logScheduleUpdateFailed(kind: AnalyticsScheduleKind, reason: String?) async {
        client.log(
            event: "schedule_update_failed",
            properties: [
                "kind": scheduleKindString(kind),
                "reason": normalizeReason(reason) ?? "unknown",
            ]
        )
    }

    func logExportCSV() async {
        client.log(event: "export_csv", properties: nil)
    }

    func logGoogleSyncSuccess() async {
        client.log(event: "google_sync_success", properties: nil)
    }

    func logGoogleSyncFailure(reason: String?) async {
        var props: [String: Any]? = nil
        if let normalized = normalizeReason(reason) {
            props = ["reason": normalized]
        }
        client.log(event: "google_sync_failure", properties: props)
    }

    func logGoogleSyncFinished(successCount: Int, failureCount: Int) async {
        let result: String
        if failureCount == 0 {
            result = "success"
        } else if successCount == 0 {
            result = "failure"
        } else {
            result = "partial"
        }
        client.log(
            event: "google_sync_finished",
            properties: [
                "success_count": successCount,
                "failure_count": failureCount,
                "result": result,
            ]
        )
    }

    func logGoogleEnabled() async {
        client.log(event: "google_enabled", properties: nil)
    }

    func logGoogleDisabled() async {
        client.log(event: "google_disabled", properties: nil)
    }

    private func measurementKindString(_ kind: AnalyticsMeasurementKind) -> String {
        switch kind {
        case .bloodPressure:
            return "bp"
        case .glucose:
            return "glucose"
        }
    }

    private func scheduleKindString(_ kind: AnalyticsScheduleKind) -> String {
        switch kind {
        case .bloodPressure:
            return "bp"
        case .glucose:
            return "glucose"
        }
    }

    private func normalizeReason(_ reason: String?) -> String? {
        guard let reason else { return nil }
        let normalized = reason.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }

        if normalized == "google_invalid_grant" || normalized == "row_sync_failed" {
            return normalized
        }

        if normalized.contains("invalid_grant") {
            return "google_invalid_grant"
        }
        if normalized.contains("network") || normalized.contains("timed out") || normalized.contains("timeout") {
            return "network"
        }
        if normalized.contains("auth") || normalized.contains("credential") || normalized.contains("token") {
            return "auth"
        }
        return "unknown"
    }
}
