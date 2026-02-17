//
//  SyncWithGoogleUseCase.swift
//  DDiary
//
//  Created by Ilia Khokhlov on 16.12.25.
//

import Foundation

enum GoogleSyncLifecyclePhase: String, Sendable {
    case started
    case progress
    case finished
}

enum GoogleSyncLifecycleUserInfoKey: String {
    case phase
    case pendingCount
    case failedCount
    case lastSyncAt
}

extension Notification.Name {
    nonisolated static let googleSyncLifecycleChanged = Notification.Name("GoogleSyncLifecycleChanged")
}

@MainActor
final class SyncWithGoogleUseCase {
    private struct SyncStatusSnapshot {
        var pendingCount: Int
        var failedCount: Int
        var lastSyncAt: Date?

        mutating func applyTransition(from previous: GoogleSyncStatus, to current: GoogleSyncStatus, syncedAt: Date) {
            switch previous {
            case .pending:
                pendingCount = max(0, pendingCount - 1)
            case .failed:
                failedCount = max(0, failedCount - 1)
            case .success:
                break
            }

            switch current {
            case .pending:
                pendingCount += 1
            case .failed:
                failedCount += 1
            case .success:
                break
            }

            if let existingLastSyncAt = lastSyncAt {
                lastSyncAt = max(existingLastSyncAt, syncedAt)
            } else {
                lastSyncAt = syncedAt
            }
        }
    }

    private let googleIntegrationRepository: any GoogleIntegrationRepository
    private let measurementsRepository: any MeasurementsRepository
    private let analyticsRepository: any AnalyticsRepository
    private let googleSheetsClient: any GoogleSheetsClient
    private var isSyncInProgress = false

    init(
        googleIntegrationRepository: any GoogleIntegrationRepository,
        measurementsRepository: any MeasurementsRepository,
        analyticsRepository: any AnalyticsRepository,
        googleSheetsClient: any GoogleSheetsClient
    ) {
        self.googleIntegrationRepository = googleIntegrationRepository
        self.measurementsRepository = measurementsRepository
        self.analyticsRepository = analyticsRepository
        self.googleSheetsClient = googleSheetsClient
    }

    /// Push pending/failed measurements to Google Sheets and update their sync status.
    func execute() async { await syncPendingMeasurements() }

    /// Schedule a best-effort sync trigger that runs only when Google is connected.
    /// This keeps value save flows fast while still starting sync immediately.
    func scheduleSyncIfConnected() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.syncPendingMeasurementsIfConnected()
        }
    }

    /// Attempt sync only when integration is connected with required credentials.
    /// No analytics failure is logged when integration is not connected.
    func syncPendingMeasurementsIfConnected() async {
        do {
            guard try await hasConnectedIntegration() else {
                log("Auto-sync skipped: integration not connected")
                return
            }
            await syncPendingMeasurements()
        } catch {
            log("Auto-sync preflight failed: \(error)")
        }
    }

    /// Push pending/failed measurements to Google Sheets and update their sync status.
    func syncPendingMeasurements() async {
        guard !isSyncInProgress else {
            log("Sync request ignored: sync already in progress")
            return
        }

        isSyncInProgress = true
        defer { isSyncInProgress = false }

        var syncSnapshot: SyncStatusSnapshot?
        publishLifecycle(.started, snapshot: nil)
        defer { publishLifecycle(.finished, snapshot: syncSnapshot) }
        log("Starting sync")
        do {
            let integration = try await googleIntegrationRepository.getOrCreate()
            log("Integration enabled=\(integration.isEnabled) spreadsheetId=\(integration.spreadsheetId ?? "nil") refreshToken=\(integration.refreshToken != nil)")
            guard
                integration.isEnabled,
                let spreadsheetId = integration.spreadsheetId,
                let refreshToken = integration.refreshToken
            else {
                log("Missing credentials or disabled; aborting")
                await analyticsRepository.logGoogleSyncFailure(reason: "Integration disabled or missing credentials")
                return
            }

            let credentials = GoogleSheetsCredentials(
                spreadsheetId: spreadsheetId,
                refreshToken: refreshToken,
                googleUserId: integration.googleUserId
            )

            do {
                try await googleSheetsClient.ensureSheetsAndHeaders(credentials: credentials)
                log("Ensured sheets and headers")
            } catch {
                if isInvalidGrantError(error) {
                    await invalidateIntegrationDueToInvalidGrant(integration: integration)
                    await analyticsRepository.logGoogleSyncFailure(reason: "google_invalid_grant")
                    return
                }
                log("Failed ensuring sheets/headers: \(error)")
                throw error
            }

            // Fetch pending/failed items
            let pendingBP = try await measurementsRepository.pendingOrFailedBPSync()
            let pendingGlucose = try await measurementsRepository.pendingOrFailedGlucoseSync()
            log("Pending BP=\(pendingBP.count) Glucose=\(pendingGlucose.count)")
            syncSnapshot = SyncStatusSnapshot(
                pendingCount: pendingBP.filter { $0.googleSyncStatus == .pending }.count
                    + pendingGlucose.filter { $0.googleSyncStatus == .pending }.count,
                failedCount: pendingBP.filter { $0.googleSyncStatus == .failed }.count
                    + pendingGlucose.filter { $0.googleSyncStatus == .failed }.count,
                lastSyncAt: nil
            )
            publishLifecycle(.progress, snapshot: syncSnapshot)

            // Sync BP
            for m in pendingBP.sorted(by: { $0.timestamp < $1.timestamp }) {
                let previousStatus = m.googleSyncStatus
                do {
                    let row = GoogleSheetsBPRow(
                        id: m.id,
                        timestamp: m.timestamp,
                        systolic: m.systolic,
                        diastolic: m.diastolic,
                        pulse: m.pulse,
                        comment: m.comment
                    )
                    try await googleSheetsClient.upsertBloodPressureRow(row, credentials: credentials)
                    m.googleSyncStatus = .success
                    m.googleLastError = nil
                    m.googleLastSyncAt = Date()
                    try await measurementsRepository.updateBP(m)
                    if let syncedAt = m.googleLastSyncAt {
                        syncSnapshot?.applyTransition(from: previousStatus, to: m.googleSyncStatus, syncedAt: syncedAt)
                    }
                    publishLifecycle(.progress, snapshot: syncSnapshot)
                    log("BP synced id=\(m.id.uuidString)")
                    await analyticsRepository.logGoogleSyncSuccess()
                } catch {
                    m.googleSyncStatus = .failed
                    m.googleLastError = String(describing: error)
                    m.googleLastSyncAt = Date()
                    try? await measurementsRepository.updateBP(m)
                    if let syncedAt = m.googleLastSyncAt {
                        syncSnapshot?.applyTransition(from: previousStatus, to: m.googleSyncStatus, syncedAt: syncedAt)
                    }
                    publishLifecycle(.progress, snapshot: syncSnapshot)
                    log("BP sync failed id=\(m.id.uuidString) error=\(m.googleLastError ?? "unknown")")
                    await analyticsRepository.logGoogleSyncFailure(reason: m.googleLastError)
                }
            }

            // Sync Glucose
            for m in pendingGlucose.sorted(by: { $0.timestamp < $1.timestamp }) {
                let previousStatus = m.googleSyncStatus
                do {
                    let row = GoogleSheetsGlucoseRow(
                        id: m.id,
                        timestamp: m.timestamp,
                        value: m.value,
                        unit: m.unit,
                        measurementType: m.measurementType,
                        mealSlot: m.mealSlot,
                        comment: m.comment
                    )
                    try await googleSheetsClient.upsertGlucoseRow(row, credentials: credentials)
                    m.googleSyncStatus = .success
                    m.googleLastError = nil
                    m.googleLastSyncAt = Date()
                    try await measurementsRepository.updateGlucose(m)
                    if let syncedAt = m.googleLastSyncAt {
                        syncSnapshot?.applyTransition(from: previousStatus, to: m.googleSyncStatus, syncedAt: syncedAt)
                    }
                    publishLifecycle(.progress, snapshot: syncSnapshot)
                    log("Glucose synced id=\(m.id.uuidString)")
                    await analyticsRepository.logGoogleSyncSuccess()
                } catch {
                    m.googleSyncStatus = .failed
                    m.googleLastError = String(describing: error)
                    m.googleLastSyncAt = Date()
                    try? await measurementsRepository.updateGlucose(m)
                    if let syncedAt = m.googleLastSyncAt {
                        syncSnapshot?.applyTransition(from: previousStatus, to: m.googleSyncStatus, syncedAt: syncedAt)
                    }
                    publishLifecycle(.progress, snapshot: syncSnapshot)
                    log("Glucose sync failed id=\(m.id.uuidString) error=\(m.googleLastError ?? "unknown")")
                    await analyticsRepository.logGoogleSyncFailure(reason: m.googleLastError)
                }
            }
        } catch {
            log("Sync failed: \(error)")
            // Repository-level failure: surface as analytics failure; individual records remain unchanged.
            await analyticsRepository.logGoogleSyncFailure(reason: String(describing: error))
        }
    }

    private func publishLifecycle(_ phase: GoogleSyncLifecyclePhase, snapshot: SyncStatusSnapshot?) {
        var userInfo: [AnyHashable: Any] = [GoogleSyncLifecycleUserInfoKey.phase.rawValue: phase.rawValue]
        if let snapshot {
            userInfo[GoogleSyncLifecycleUserInfoKey.pendingCount.rawValue] = snapshot.pendingCount
            userInfo[GoogleSyncLifecycleUserInfoKey.failedCount.rawValue] = snapshot.failedCount
            if let lastSyncAt = snapshot.lastSyncAt {
                userInfo[GoogleSyncLifecycleUserInfoKey.lastSyncAt.rawValue] = lastSyncAt
            }
        }

        NotificationCenter.default.post(
            name: .googleSyncLifecycleChanged,
            object: nil,
            userInfo: userInfo
        )
    }

    private func isInvalidGrantError(_ error: Error) -> Bool {
        guard case let GoogleSheetsClientError.httpError(statusCode, body) = error else {
            return false
        }
        guard statusCode == 400 else { return false }
        guard let body else { return false }
        return body.localizedCaseInsensitiveContains("invalid_grant")
    }

    private func invalidateIntegrationDueToInvalidGrant(integration: GoogleIntegration) async {
        integration.isEnabled = false
        integration.refreshToken = nil
        do {
            try await googleIntegrationRepository.update(integration)
            log("Refresh token is invalid/revoked; integration disabled until reconnect")
        } catch {
            log("Failed to persist invalid token state: \(error)")
        }
    }

    private func log(_ message: String) {
        #if DEBUG
        print("[GoogleSync] \(message)")
        #endif
    }

    private func hasConnectedIntegration() async throws -> Bool {
        let integration = try await googleIntegrationRepository.getOrCreate()
        return integration.isEnabled
            && integration.spreadsheetId != nil
            && integration.refreshToken != nil
    }
}
