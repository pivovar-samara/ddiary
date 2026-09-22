//
//  AnalyticsEventFactory.swift
//  DDiary
//

import Foundation

/// Single source of truth for analytics event names and properties.
///
/// Every provider is fed from here, so both Amplitude and Firebase always see identical
/// events. No vendor SDK is imported, which keeps the mapping unit-testable on its own.
///
/// Event names must stay valid for Google Analytics 4: start with a letter, `[A-Za-z0-9_]`
/// only, at most 40 characters, and never the reserved `firebase_` / `google_` / `ga_`
/// prefixes. `AnalyticsEventFactoryTests` enforces this for every event below.
nonisolated enum AnalyticsEventFactory {
    /// `app_open` is a *suggested* Firebase event, not a reserved or automatically collected one.
    /// The SDK ships it as a public constant (`kFIREventAppOpen` / `AnalyticsEventAppOpen`) whose
    /// own documentation says developers log it to supplement the automatic session events. It is
    /// absent from GA4's reserved-name list, so logging it manually is correct and does not
    /// collide with anything Firebase reports on its own.
    static func appOpen() -> AnalyticsEvent {
        AnalyticsEvent(name: "app_open")
    }

    static func measurementLogged(kind: AnalyticsMeasurementKind) -> AnalyticsEvent {
        AnalyticsEvent(
            name: "measurement_logged",
            properties: ["kind": .string(measurementKindString(kind))]
        )
    }

    static func measurementSaveFailed(
        kind: AnalyticsMeasurementKind,
        reason: String?
    ) -> AnalyticsEvent {
        AnalyticsEvent(
            name: "measurement_save_failed",
            properties: [
                "kind": .string(measurementKindString(kind)),
                "reason": .string(normalizeReason(reason) ?? "unknown"),
            ]
        )
    }

    static func scheduleUpdated(kind: AnalyticsScheduleKind) -> AnalyticsEvent {
        AnalyticsEvent(
            name: "schedule_updated",
            properties: ["kind": .string(scheduleKindString(kind))]
        )
    }

    static func scheduleUpdateFailed(
        kind: AnalyticsScheduleKind,
        reason: String?
    ) -> AnalyticsEvent {
        AnalyticsEvent(
            name: "schedule_update_failed",
            properties: [
                "kind": .string(scheduleKindString(kind)),
                "reason": .string(normalizeReason(reason) ?? "unknown"),
            ]
        )
    }

    static func exportCSV() -> AnalyticsEvent {
        AnalyticsEvent(name: "export_csv")
    }

    static func gsheetsSyncSuccess() -> AnalyticsEvent {
        AnalyticsEvent(name: "gsheets_sync_success")
    }

    static func gsheetsSyncFailure(reason: String?) -> AnalyticsEvent {
        // Unlike measurementSaveFailed, a blank reason omits the property entirely rather
        // than falling back to "unknown". Preserved deliberately from the original mapping.
        guard let normalized = normalizeReason(reason) else {
            return AnalyticsEvent(name: "gsheets_sync_failure")
        }
        return AnalyticsEvent(
            name: "gsheets_sync_failure",
            properties: ["reason": .string(normalized)]
        )
    }

    static func gsheetsSyncFinished(successCount: Int, failureCount: Int) -> AnalyticsEvent {
        let result: String
        if failureCount == 0 {
            result = "success"
        } else if successCount == 0 {
            result = "failure"
        } else {
            result = "partial"
        }
        return AnalyticsEvent(
            name: "gsheets_sync_finished",
            properties: [
                "success_count": .int(successCount),
                "failure_count": .int(failureCount),
                "result": .string(result),
            ]
        )
    }

    static func gsheetsEnabled() -> AnalyticsEvent {
        AnalyticsEvent(name: "gsheets_enabled")
    }

    static func gsheetsDisabled() -> AnalyticsEvent {
        AnalyticsEvent(name: "gsheets_disabled")
    }

    // MARK: - Mapping helpers

    static func measurementKindString(_ kind: AnalyticsMeasurementKind) -> String {
        switch kind {
        case .bloodPressure:
            return "bp"
        case .glucose:
            return "glucose"
        }
    }

    static func scheduleKindString(_ kind: AnalyticsScheduleKind) -> String {
        switch kind {
        case .bloodPressure:
            return "bp"
        case .glucose:
            return "glucose"
        }
    }

    /// Collapses a free-form error description into a closed set of buckets.
    ///
    /// This is a privacy invariant, not a formatting helper: call sites pass
    /// `String(describing: error)`, which can carry URLs, account identifiers or tokens.
    /// Because this factory is the only place a raw string becomes an event property,
    /// every provider receives the sanitized value and there is exactly one function to audit.
    static func normalizeReason(_ reason: String?) -> String? {
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
