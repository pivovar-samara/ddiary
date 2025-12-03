import Foundation

public protocol AmplitudeClient: Sendable {
    func log(event: String, properties: [String: Sendable]?)
}

public struct ConsoleAmplitudeClient: AmplitudeClient {
    public init() {}
    public func log(event: String, properties: [String: Sendable]?) {
        if let properties {
            print("[Amplitude] \(event) props=\(properties)")
        } else {
            print("[Amplitude] \(event)")
        }
    }
}

final class AmplitudeAnalyticsRepository: AnalyticsRepository, @unchecked Sendable {
    private let client: AmplitudeClient

    init(client: AmplitudeClient = ConsoleAmplitudeClient()) {
        self.client = client
    }

    // MARK: - AnalyticsRepository
    func logAppOpen() async {
        // Here you'd call the real Amplitude SDK, e.g., Amplitude.instance().logEvent("app_open")
        client.log(event: "app_open", properties: nil)
    }

    func logMeasurementLogged(kind: AnalyticsMeasurementKind) async {
        let kindString: String
        switch kind {
        case .bloodPressure: kindString = "bp"
        case .glucose: kindString = "glucose"
        }
        client.log(event: "measurement_logged", properties: ["kind": kindString])
    }

    func logScheduleUpdated(kind: AnalyticsScheduleKind) async {
        let kindString: String
        switch kind {
        case .bloodPressure: kindString = "bp"
        case .glucose: kindString = "glucose"
        }
        client.log(event: "schedule_updated", properties: ["kind": kindString])
    }

    func logExportCSV() async {
        client.log(event: "export_csv", properties: nil)
    }

    func logGoogleSyncSuccess() async {
        client.log(event: "google_sync_success", properties: nil)
    }

    func logGoogleSyncFailure(reason: String?) async {
        var props: [String: Sendable]? = nil
        if let reason { props = ["reason": reason] }
        client.log(event: "google_sync_failure", properties: props)
    }

    func logGoogleEnabled() async {
        client.log(event: "google_enabled", properties: nil)
    }

    func logGoogleDisabled() async {
        client.log(event: "google_disabled", properties: nil)
    }
}
