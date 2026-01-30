//
//  SyncWithGoogleUseCase.swift
//  DDiary
//
//  Created by Ilia Khokhlov on 16.12.25.
//

import Foundation

@MainActor
final class SyncWithGoogleUseCase {
    private let googleIntegrationRepository: any GoogleIntegrationRepository
    private let measurementsRepository: any MeasurementsRepository
    private let analyticsRepository: any AnalyticsRepository
    private let googleSheetsClient: any GoogleSheetsClient

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

    /// Push pending/failed measurements to Google Sheets and update their sync status.
    func syncPendingMeasurements() async {
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
                log("Failed ensuring sheets/headers: \(error)")
                throw error
            }

            // Fetch pending/failed items
            let pendingBP = try await measurementsRepository.pendingOrFailedBPSync()
            let pendingGlucose = try await measurementsRepository.pendingOrFailedGlucoseSync()
            log("Pending BP=\(pendingBP.count) Glucose=\(pendingGlucose.count)")

            // Sync BP
            for m in pendingBP.sorted(by: { $0.timestamp < $1.timestamp }) {
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
                    log("BP synced id=\(m.id.uuidString)")
                    await analyticsRepository.logGoogleSyncSuccess()
                } catch {
                    m.googleSyncStatus = .failed
                    m.googleLastError = String(describing: error)
                    m.googleLastSyncAt = Date()
                    try? await measurementsRepository.updateBP(m)
                    log("BP sync failed id=\(m.id.uuidString) error=\(m.googleLastError ?? "unknown")")
                    await analyticsRepository.logGoogleSyncFailure(reason: m.googleLastError)
                }
            }

            // Sync Glucose
            for m in pendingGlucose.sorted(by: { $0.timestamp < $1.timestamp }) {
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
                    log("Glucose synced id=\(m.id.uuidString)")
                    await analyticsRepository.logGoogleSyncSuccess()
                } catch {
                    m.googleSyncStatus = .failed
                    m.googleLastError = String(describing: error)
                    m.googleLastSyncAt = Date()
                    try? await measurementsRepository.updateGlucose(m)
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

    private func log(_ message: String) {
        #if DEBUG
        print("[GoogleSync] \(message)")
        #endif
    }
}
