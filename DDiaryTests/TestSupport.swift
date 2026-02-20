//
//  TestSupport.swift
//  DDiary
//
//  Created by Ilia Khokhlov on 10.12.25.
//

import XCTest
@testable import DDiary

// Shared test error
enum TestError: Error { case forced }

// Shared analytics mock
final class MockAnalyticsRepository: AnalyticsRepository, @unchecked Sendable {
    private(set) var appOpenCount = 0
    private(set) var measurementLogged: [AnalyticsMeasurementKind] = []
    private(set) var measurementSaveFailed: [(kind: AnalyticsMeasurementKind, reason: String?)] = []
    private(set) var scheduleUpdated: [AnalyticsScheduleKind] = []
    private(set) var scheduleUpdateFailed: [(kind: AnalyticsScheduleKind, reason: String?)] = []
    private(set) var exportCSVCount = 0
    private(set) var googleSyncSuccessCount = 0
    private(set) var googleSyncFailureReasons: [String?] = []
    private(set) var googleSyncFinished: [(successCount: Int, failureCount: Int)] = []
    private(set) var googleEnabledCount = 0
    private(set) var googleDisabledCount = 0

    func logAppOpen() async { appOpenCount += 1 }
    func logMeasurementLogged(kind: AnalyticsMeasurementKind) async { measurementLogged.append(kind) }
    func logMeasurementSaveFailed(kind: AnalyticsMeasurementKind, reason: String?) async {
        measurementSaveFailed.append((kind: kind, reason: reason))
    }
    func logScheduleUpdated(kind: AnalyticsScheduleKind) async { scheduleUpdated.append(kind) }
    func logScheduleUpdateFailed(kind: AnalyticsScheduleKind, reason: String?) async {
        scheduleUpdateFailed.append((kind: kind, reason: reason))
    }
    func logExportCSV() async { exportCSVCount += 1 }
    func logGoogleSyncSuccess() async { googleSyncSuccessCount += 1 }
    func logGoogleSyncFailure(reason: String?) async { googleSyncFailureReasons.append(reason) }
    func logGoogleSyncFinished(successCount: Int, failureCount: Int) async {
        googleSyncFinished.append((successCount: successCount, failureCount: failureCount))
    }
    func logGoogleEnabled() async { googleEnabledCount += 1 }
    func logGoogleDisabled() async { googleDisabledCount += 1 }
}

// GoogleSheets client test double
struct RecordingGoogleSheetsClient: GoogleSheetsClient, Sendable {
    enum Mode { case succeed, fail(Error) }
    let mode: Mode
    init(mode: Mode = .succeed) { self.mode = mode }

    func appendBloodPressureRow(_ row: GoogleSheetsBPRow, credentials: GoogleSheetsCredentials) async throws {
        switch mode { case .succeed: return; case .fail(let e): throw e }
    }

    func appendGlucoseRow(_ row: GoogleSheetsGlucoseRow, credentials: GoogleSheetsCredentials) async throws {
        switch mode { case .succeed: return; case .fail(let e): throw e }
    }
}

// Async throws helper
extension XCTestCase {
    func XCTAssertThrowsErrorAsync(_ expression: @autoclosure @escaping () async throws -> Void, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            try await expression()
            XCTFail("Expected error to be thrown", file: file, line: line)
        } catch {
            // expected
        }
    }
}
