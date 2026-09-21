//
//  AnalyticsEventFactoryTests.swift
//  DDiaryTests
//

import Foundation
import XCTest
@testable import DDiary

final class AnalyticsEventFactoryTests: XCTestCase {

    // MARK: - Names and properties

    func test_appOpen_mapsToAppOpenEventWithoutProperties() {
        let event = AnalyticsEventFactory.appOpen()
        XCTAssertEqual(event.name, "app_open")
        XCTAssertTrue(event.properties.isEmpty)
        XCTAssertNil(event.objectProperties)
    }

    func test_measurementLogged_withBloodPressure_mapsKindToBP() {
        let event = AnalyticsEventFactory.measurementLogged(kind: .bloodPressure)
        XCTAssertEqual(event, AnalyticsEvent(name: "measurement_logged", properties: ["kind": .string("bp")]))
    }

    func test_measurementLogged_withGlucose_mapsKindToGlucose() {
        let event = AnalyticsEventFactory.measurementLogged(kind: .glucose)
        XCTAssertEqual(event, AnalyticsEvent(name: "measurement_logged", properties: ["kind": .string("glucose")]))
    }

    func test_scheduleUpdated_withBloodPressure_mapsKindToBP() {
        let event = AnalyticsEventFactory.scheduleUpdated(kind: .bloodPressure)
        XCTAssertEqual(event, AnalyticsEvent(name: "schedule_updated", properties: ["kind": .string("bp")]))
    }

    func test_exportCSV_mapsToExportCSVEventWithoutProperties() {
        let event = AnalyticsEventFactory.exportCSV()
        XCTAssertEqual(event.name, "export_csv")
        XCTAssertNil(event.objectProperties)
    }

    func test_gsheetsEnabledAndDisabled_useGsheetsPrefix() {
        XCTAssertEqual(AnalyticsEventFactory.gsheetsEnabled().name, "gsheets_enabled")
        XCTAssertEqual(AnalyticsEventFactory.gsheetsDisabled().name, "gsheets_disabled")
        XCTAssertEqual(AnalyticsEventFactory.gsheetsSyncSuccess().name, "gsheets_sync_success")
    }

    // MARK: - Reason normalization

    func test_measurementSaveFailed_withNilReason_fallsBackToUnknown() {
        let event = AnalyticsEventFactory.measurementSaveFailed(kind: .bloodPressure, reason: nil)
        XCTAssertEqual(event.properties["reason"], .string("unknown"))
    }

    func test_measurementSaveFailed_withNetworkErrorText_bucketsReasonAsNetwork() {
        let event = AnalyticsEventFactory.measurementSaveFailed(
            kind: .glucose,
            reason: "The request timed out while contacting the server"
        )
        XCTAssertEqual(event.properties["reason"], .string("network"))
    }

    func test_measurementSaveFailed_withTokenErrorText_bucketsReasonAsAuth() {
        let event = AnalyticsEventFactory.measurementSaveFailed(
            kind: .glucose,
            reason: "Missing refresh token for account"
        )
        XCTAssertEqual(event.properties["reason"], .string("auth"))
    }

    func test_scheduleUpdateFailed_withWhitespaceOnlyReason_fallsBackToUnknown() {
        let event = AnalyticsEventFactory.scheduleUpdateFailed(kind: .glucose, reason: "   \n  ")
        XCTAssertEqual(event.properties["reason"], .string("unknown"))
    }

    func test_normalizeReason_withUnrecognizedText_returnsUnknown() {
        XCTAssertEqual(AnalyticsEventFactory.normalizeReason("something else entirely"), "unknown")
    }

    func test_normalizeReason_withInvalidGrantText_returnsGoogleInvalidGrant() {
        XCTAssertEqual(
            AnalyticsEventFactory.normalizeReason("Error Domain=google code=400 invalid_grant"),
            "google_invalid_grant"
        )
    }

    func test_normalizeReason_withPassthroughBuckets_returnsThemUnchanged() {
        XCTAssertEqual(AnalyticsEventFactory.normalizeReason("row_sync_failed"), "row_sync_failed")
        XCTAssertEqual(AnalyticsEventFactory.normalizeReason("google_invalid_grant"), "google_invalid_grant")
    }

    // MARK: - Google Sheets sync

    /// Pins a deliberate asymmetry: a blank reason omits the property entirely here,
    /// unlike measurementSaveFailed which falls back to "unknown".
    func test_gsheetsSyncFailure_withNilReason_omitsPropertiesEntirely() {
        let event = AnalyticsEventFactory.gsheetsSyncFailure(reason: nil)
        XCTAssertEqual(event.name, "gsheets_sync_failure")
        XCTAssertTrue(event.properties.isEmpty)
        XCTAssertNil(event.objectProperties)
    }

    func test_gsheetsSyncFailure_withInvalidGrantText_normalizesToGoogleInvalidGrant() {
        let event = AnalyticsEventFactory.gsheetsSyncFailure(reason: "google_invalid_grant")
        XCTAssertEqual(event.properties["reason"], .string("google_invalid_grant"))
    }

    func test_gsheetsSyncFinished_withNoFailures_setsResultSuccess() {
        let event = AnalyticsEventFactory.gsheetsSyncFinished(successCount: 3, failureCount: 0)
        XCTAssertEqual(event.properties["result"], .string("success"))
        XCTAssertEqual(event.properties["success_count"], .int(3))
        XCTAssertEqual(event.properties["failure_count"], .int(0))
    }

    func test_gsheetsSyncFinished_withNoSuccesses_setsResultFailure() {
        let event = AnalyticsEventFactory.gsheetsSyncFinished(successCount: 0, failureCount: 2)
        XCTAssertEqual(event.properties["result"], .string("failure"))
    }

    func test_gsheetsSyncFinished_withMixedCounts_setsResultPartial() {
        let event = AnalyticsEventFactory.gsheetsSyncFinished(successCount: 1, failureCount: 2)
        XCTAssertEqual(event.properties["result"], .string("partial"))
    }

    // MARK: - GA4 validity guards

    func test_allEventNames_areValidForFirebaseAnalytics() {
        for event in Self.allCanonicalEvents {
            assertValidGA4Name(event.name, kind: "event name")
            XCTAssertFalse(
                Self.ga4ReservedEventNames.contains(event.name),
                "\(event.name) is a reserved GA4 event name"
            )
        }
    }

    func test_allPropertyNames_areValidForFirebaseAnalytics() {
        for event in Self.allCanonicalEvents {
            XCTAssertLessThanOrEqual(
                event.properties.count, 25,
                "\(event.name) exceeds the GA4 limit of 25 parameters"
            )
            for (key, value) in event.properties {
                assertValidGA4Name(key, kind: "parameter name of \(event.name)")
                if case let .string(stringValue) = value {
                    XCTAssertLessThanOrEqual(
                        stringValue.count, 100,
                        "\(event.name).\(key) exceeds the GA4 100-character value limit"
                    )
                }
            }
        }
    }

    // MARK: - Fan-out

    func test_allRepositoryMethods_emitCanonicalEventNamesToEverySink() async {
        let first = RecordingAnalyticsEventSink()
        let second = RecordingAnalyticsEventSink()
        let repository = CompositeAnalyticsRepository(sinks: [first, second])

        await repository.logAppOpen()
        await repository.logMeasurementLogged(kind: .bloodPressure)
        await repository.logMeasurementSaveFailed(kind: .bloodPressure, reason: nil)
        await repository.logScheduleUpdated(kind: .glucose)
        await repository.logScheduleUpdateFailed(kind: .glucose, reason: nil)
        await repository.logExportCSV()
        await repository.logGoogleSyncSuccess()
        await repository.logGoogleSyncFailure(reason: nil)
        await repository.logGoogleSyncFinished(successCount: 1, failureCount: 0)
        await repository.logGoogleEnabled()
        await repository.logGoogleDisabled()

        XCTAssertEqual(first.events, second.events)
        XCTAssertEqual(
            first.names,
            [
                "app_open",
                "measurement_logged",
                "measurement_save_failed",
                "schedule_updated",
                "schedule_update_failed",
                "export_csv",
                "gsheets_sync_success",
                "gsheets_sync_failure",
                "gsheets_sync_finished",
                "gsheets_enabled",
                "gsheets_disabled",
            ]
        )
    }

    func test_withNoSinks_doesNotCrash() async {
        let repository = CompositeAnalyticsRepository(sinks: [])
        await repository.logAppOpen()
    }

    // MARK: - Helpers

    private func assertValidGA4Name(
        _ name: String,
        kind: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertLessThanOrEqual(name.count, 40, "\(kind) '\(name)' exceeds 40 characters", file: file, line: line)
        XCTAssertNotNil(
            name.range(of: "^[A-Za-z][A-Za-z0-9_]*$", options: .regularExpression),
            "\(kind) '\(name)' must start with a letter and contain only letters, digits and underscores",
            file: file, line: line
        )
        for prefix in ["firebase_", "google_", "ga_"] {
            XCTAssertFalse(
                name.hasPrefix(prefix),
                "\(kind) '\(name)' uses the reserved GA4 prefix '\(prefix)'",
                file: file, line: line
            )
        }
    }

    private static let allCanonicalEvents: [AnalyticsEvent] = [
        AnalyticsEventFactory.appOpen(),
        AnalyticsEventFactory.measurementLogged(kind: .bloodPressure),
        AnalyticsEventFactory.measurementSaveFailed(kind: .bloodPressure, reason: "boom"),
        AnalyticsEventFactory.scheduleUpdated(kind: .glucose),
        AnalyticsEventFactory.scheduleUpdateFailed(kind: .glucose, reason: "boom"),
        AnalyticsEventFactory.exportCSV(),
        AnalyticsEventFactory.gsheetsSyncSuccess(),
        AnalyticsEventFactory.gsheetsSyncFailure(reason: "boom"),
        AnalyticsEventFactory.gsheetsSyncFinished(successCount: 1, failureCount: 1),
        AnalyticsEventFactory.gsheetsEnabled(),
        AnalyticsEventFactory.gsheetsDisabled(),
    ]

    /// https://support.google.com/analytics/answer/13316687 — mobile reserved event names.
    private static let ga4ReservedEventNames: Set<String> = [
        "ad_activeview", "ad_click", "ad_exposure", "ad_query", "ad_reward", "adunit_exposure",
        "app_clear_data", "app_exception", "app_install", "app_remove", "app_store_refund",
        "app_update", "app_upgrade", "dynamic_link_app_open", "dynamic_link_app_update",
        "dynamic_link_first_open", "error", "firebase_campaign", "firebase_in_app_message_action",
        "firebase_in_app_message_dismiss", "firebase_in_app_message_impression", "first_open",
        "first_visit", "notification_dismiss", "notification_foreground", "notification_open",
        "notification_receive", "notification_send", "os_update", "session_start", "user_engagement",
    ]
}
