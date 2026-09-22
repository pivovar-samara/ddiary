//
//  TestSupport.swift
//  DDiary
//
//  Created by Ilia Khokhlov on 10.12.25.
//

import Foundation
import XCTest
@testable import DDiary

// Shared test error
enum TestError: Error { case forced }

// MARK: - InMemoryTokenStorage

/// In-memory TokenStorage for use in tests that involve the repository layer.
final class InMemoryTokenStorage: TokenStorage {
    private var store: [String: String] = [:]

    func read(key: String) -> String? { store[key] }
    func write(_ token: String, key: String) { store[key] = token }
    func delete(key: String) { store.removeValue(forKey: key) }
}

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

// Records every event handed to a sink so event mapping can be asserted exactly.
// Unlike MockAnalyticsRepository (only touched from @MainActor tests) this one is called
// from CompositeAnalyticsRepository's nonisolated path, so it needs real locking.
final class RecordingAnalyticsEventSink: AnalyticsEventSink, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [AnalyticsEvent] = []

    var events: [AnalyticsEvent] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    var names: [String] { events.map(\.name) }

    func send(_ event: AnalyticsEvent) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(event)
    }
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
