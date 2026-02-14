import XCTest
@testable import DDiary

@MainActor
final class SettingsViewModelSaveSettingsTests: XCTestCase {
    func test_saveSettings_callsSchedulesUpdaterOnceAfterSave() async throws {
        let settingsRepository = SpySettingsRepository()
        let updater = SpySchedulesUpdater()
        let measurementsRepository = MockMeasurementsRepository()
        let sut = makeSUT(
            settingsRepository: settingsRepository,
            measurementsRepository: measurementsRepository,
            schedulesUpdater: updater
        )

        sut.glucoseMin = 4.4
        await sut.saveSettings()

        XCTAssertEqual(settingsRepository.saveCount, 1)
        XCTAssertEqual(updater.callCount, 1)
        XCTAssertEqual(settingsRepository.savedSettings?.glucoseMin, 4.4)
        XCTAssertNil(sut.errorMessage)
    }

    func test_saveSettings_whenSchedulingFails_keepsSavedSettingsAndShowsError() async throws {
        let settingsRepository = SpySettingsRepository()
        let updater = SpySchedulesUpdater()
        updater.error = TestError.forced
        let measurementsRepository = MockMeasurementsRepository()
        let sut = makeSUT(
            settingsRepository: settingsRepository,
            measurementsRepository: measurementsRepository,
            schedulesUpdater: updater
        )

        sut.bpSystolicMax = 150
        await sut.saveSettings()

        XCTAssertEqual(settingsRepository.saveCount, 1)
        XCTAssertEqual(updater.callCount, 1)
        XCTAssertEqual(settingsRepository.savedSettings?.bpSystolicMax, 150)
        XCTAssertEqual(sut.errorMessage, "Settings saved, but reminders could not be updated.")
    }

    func test_saveSettings_persistsCycleAndBedtimeFlags_beforeScheduling() async throws {
        let settingsRepository = SpySettingsRepository()
        let updater = SpySchedulesUpdater()
        let measurementsRepository = MockMeasurementsRepository()
        let sut = makeSUT(
            settingsRepository: settingsRepository,
            measurementsRepository: measurementsRepository,
            schedulesUpdater: updater
        )

        sut.enableDailyCycleMode = true
        sut.enableBeforeMeal = true
        sut.enableAfterMeal2h = false
        sut.enableBedtime = true
        sut.bedtimeSlotEnabled = true

        await sut.saveSettings()

        XCTAssertEqual(settingsRepository.saveCount, 1)
        XCTAssertEqual(updater.callCount, 1)
        XCTAssertEqual(settingsRepository.savedSettings?.enableDailyCycleMode, true)
        XCTAssertEqual(settingsRepository.savedSettings?.enableBedtime, true)
        XCTAssertEqual(settingsRepository.savedSettings?.bedtimeSlotEnabled, true)
        XCTAssertEqual(settingsRepository.savedSettings?.enableAfterMeal2h, false)
    }

    func test_refreshCloudBackedState_picksUpLaterCloudRestoredIntegration() async throws {
        let settingsRepository = SpySettingsRepository()
        let updater = SpySchedulesUpdater()
        let measurementsRepository = MockMeasurementsRepository()

        let placeholder = GoogleIntegration()
        placeholder.isEnabled = false

        let restored = GoogleIntegration()
        restored.isEnabled = true
        restored.refreshToken = "rt"
        restored.spreadsheetId = "sheet"
        restored.googleUserId = "user@example.com"

        let googleRepository = RotatingGoogleIntegrationRepository(integrations: [placeholder, restored])
        let sut = makeSUT(
            settingsRepository: settingsRepository,
            measurementsRepository: measurementsRepository,
            schedulesUpdater: updater,
            googleIntegrationRepository: googleRepository
        )

        await sut.loadSettings()
        XCTAssertFalse(sut.isGoogleEnabled)
        XCTAssertEqual(sut.googleSummary, "Not connected")

        await sut.refreshCloudBackedState()
        XCTAssertTrue(sut.isGoogleEnabled)
        XCTAssertEqual(sut.googleSummary, "Connected (user@example.com)")
        XCTAssertGreaterThanOrEqual(googleRepository.getOrCreateCallCount, 2)
    }

    func test_refreshSyncStatus_updatesGoogleSummaryFromLatestIntegrationState() async throws {
        let settingsRepository = SpySettingsRepository()
        let updater = SpySchedulesUpdater()
        let measurementsRepository = MockMeasurementsRepository()

        let connected = GoogleIntegration()
        connected.isEnabled = true
        connected.refreshToken = "rt"
        connected.spreadsheetId = "sheet"
        connected.googleUserId = "user@example.com"

        let disconnected = GoogleIntegration()
        disconnected.isEnabled = false
        disconnected.refreshToken = nil
        disconnected.spreadsheetId = "sheet"
        disconnected.googleUserId = "user@example.com"

        let googleRepository = RotatingGoogleIntegrationRepository(integrations: [connected, disconnected])
        let sut = makeSUT(
            settingsRepository: settingsRepository,
            measurementsRepository: measurementsRepository,
            schedulesUpdater: updater,
            googleIntegrationRepository: googleRepository
        )

        await sut.loadSettings()
        XCTAssertTrue(sut.isGoogleEnabled)
        XCTAssertEqual(sut.googleSummary, "Connected (user@example.com)")

        await sut.refreshSyncStatus()
        XCTAssertFalse(sut.isGoogleEnabled)
        XCTAssertEqual(sut.googleSummary, "Not connected")
    }

    func test_refreshSyncStatus_keepsSummaryWhileGoogleOperationIsInProgress() async throws {
        let settingsRepository = SpySettingsRepository()
        let updater = SpySchedulesUpdater()
        let measurementsRepository = MockMeasurementsRepository()

        let disconnected = GoogleIntegration()
        disconnected.isEnabled = false
        disconnected.refreshToken = nil
        disconnected.spreadsheetId = nil

        let googleRepository = RotatingGoogleIntegrationRepository(integrations: [disconnected])
        let sut = makeSUT(
            settingsRepository: settingsRepository,
            measurementsRepository: measurementsRepository,
            schedulesUpdater: updater,
            googleIntegrationRepository: googleRepository
        )

        sut.googleSummary = L10n.settingsGoogleSummarySyncing
        sut.isGoogleOperationInProgress = true

        await sut.refreshSyncStatus()

        XCTAssertEqual(sut.googleSummary, L10n.settingsGoogleSummarySyncing)
        XCTAssertFalse(sut.isGoogleEnabled)
    }

    func test_progressLifecycleSnapshot_updatesStatusWithoutRefreshingMeasurements() async throws {
        let settingsRepository = SpySettingsRepository()
        let updater = SpySchedulesUpdater()
        let measurementsRepository = CountingMeasurementsRepository()
        try await measurementsRepository.insertBP(
            BPMeasurement(timestamp: Date(), systolic: 120, diastolic: 80, pulse: 70, comment: nil)
        )

        let sut = makeSUT(
            settingsRepository: settingsRepository,
            measurementsRepository: measurementsRepository,
            schedulesUpdater: updater
        )

        await sut.loadSettings()

        let pendingFetchCallCountBeforeProgress = measurementsRepository.pendingOrFailedBPSyncCallCount
            + measurementsRepository.pendingOrFailedGlucoseSyncCallCount
        let fullFetchCallCountBeforeProgress = measurementsRepository.bpMeasurementsCallCount
            + measurementsRepository.glucoseMeasurementsCallCount
        let snapshotSyncDate = Date(timeIntervalSince1970: 12_345)

        NotificationCenter.default.post(
            name: .googleSyncLifecycleChanged,
            object: nil,
            userInfo: [
                GoogleSyncLifecycleUserInfoKey.phase.rawValue: GoogleSyncLifecyclePhase.progress.rawValue,
                GoogleSyncLifecycleUserInfoKey.pendingCount.rawValue: 7,
                GoogleSyncLifecycleUserInfoKey.failedCount.rawValue: 3,
                GoogleSyncLifecycleUserInfoKey.lastSyncAt.rawValue: snapshotSyncDate
            ]
        )
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(sut.pendingCount, 7)
        XCTAssertEqual(sut.failedCount, 3)
        XCTAssertEqual(sut.lastSyncAt, snapshotSyncDate)
        XCTAssertEqual(
            measurementsRepository.pendingOrFailedBPSyncCallCount + measurementsRepository.pendingOrFailedGlucoseSyncCallCount,
            pendingFetchCallCountBeforeProgress
        )
        XCTAssertEqual(
            measurementsRepository.bpMeasurementsCallCount + measurementsRepository.glucoseMeasurementsCallCount,
            fullFetchCallCountBeforeProgress
        )
    }

    private func makeSUT(
        settingsRepository: SpySettingsRepository,
        measurementsRepository: any MeasurementsRepository,
        schedulesUpdater: SpySchedulesUpdater,
        googleIntegrationRepository: GoogleIntegrationRepository = MockGoogleIntegrationRepository()
    ) -> SettingsViewModel {
        SettingsViewModel(
            settingsRepository: settingsRepository,
            googleIntegrationRepository: googleIntegrationRepository,
            exportCSVUseCase: ExportCSVUseCase(measurementsRepository: measurementsRepository),
            measurementsRepository: measurementsRepository,
            googleSheetsClient: RecordingGoogleSheetsClient(),
            schedulesUpdater: schedulesUpdater
        )
    }
}

@MainActor
private final class CountingMeasurementsRepository: MeasurementsRepository {
    private var bp: [UUID: BPMeasurement] = [:]
    private var glucose: [UUID: GlucoseMeasurement] = [:]

    private(set) var bpMeasurementsCallCount: Int = 0
    private(set) var glucoseMeasurementsCallCount: Int = 0
    private(set) var pendingOrFailedBPSyncCallCount: Int = 0
    private(set) var pendingOrFailedGlucoseSyncCallCount: Int = 0

    func insertBP(_ measurement: BPMeasurement) async throws {
        bp[measurement.id] = measurement
    }

    func updateBP(_ measurement: BPMeasurement) async throws {
        bp[measurement.id] = measurement
    }

    func deleteBP(_ measurement: BPMeasurement) async throws {
        bp.removeValue(forKey: measurement.id)
    }

    func bpMeasurement(id: UUID) async throws -> BPMeasurement? {
        bp[id]
    }

    func bpMeasurements(from: Date, to: Date) async throws -> [BPMeasurement] {
        bpMeasurementsCallCount += 1
        return bp.values
            .filter { $0.timestamp >= from && $0.timestamp <= to }
            .sorted { $0.timestamp < $1.timestamp }
    }

    func pendingOrFailedBPSync() async throws -> [BPMeasurement] {
        pendingOrFailedBPSyncCallCount += 1
        return bp.values
            .filter { $0.googleSyncStatus == .pending || $0.googleSyncStatus == .failed }
            .sorted { $0.timestamp < $1.timestamp }
    }

    func insertGlucose(_ measurement: GlucoseMeasurement) async throws {
        glucose[measurement.id] = measurement
    }

    func updateGlucose(_ measurement: GlucoseMeasurement) async throws {
        glucose[measurement.id] = measurement
    }

    func deleteGlucose(_ measurement: GlucoseMeasurement) async throws {
        glucose.removeValue(forKey: measurement.id)
    }

    func glucoseMeasurement(id: UUID) async throws -> GlucoseMeasurement? {
        glucose[id]
    }

    func glucoseMeasurements(from: Date, to: Date) async throws -> [GlucoseMeasurement] {
        glucoseMeasurementsCallCount += 1
        return glucose.values
            .filter { $0.timestamp >= from && $0.timestamp <= to }
            .sorted { $0.timestamp < $1.timestamp }
    }

    func pendingOrFailedGlucoseSync() async throws -> [GlucoseMeasurement] {
        pendingOrFailedGlucoseSyncCallCount += 1
        return glucose.values
            .filter { $0.googleSyncStatus == .pending || $0.googleSyncStatus == .failed }
            .sorted { $0.timestamp < $1.timestamp }
    }
}

@MainActor
private final class SpySettingsRepository: SettingsRepository {
    private var settings: UserSettings?
    private(set) var saveCount: Int = 0
    private(set) var savedSettings: UserSettings?

    func getOrCreate() async throws -> UserSettings {
        if let settings { return settings }
        let settings = UserSettings.default()
        self.settings = settings
        return settings
    }

    func save(_ settings: UserSettings) async throws {
        saveCount += 1
        self.settings = settings
        self.savedSettings = settings
    }

    func update(_ settings: UserSettings) async throws {
        self.settings = settings
    }
}

@MainActor
private final class SpySchedulesUpdater: SchedulesUpdating {
    var error: Error?
    private(set) var callCount: Int = 0

    func scheduleFromCurrentSettings() async throws {
        callCount += 1
        if let error {
            throw error
        }
    }
}

@MainActor
private final class RotatingGoogleIntegrationRepository: GoogleIntegrationRepository {
    private var integrations: [GoogleIntegration]
    private var index: Int = 0
    private(set) var getOrCreateCallCount: Int = 0

    init(integrations: [GoogleIntegration]) {
        self.integrations = integrations
    }

    func getOrCreate() async throws -> GoogleIntegration {
        getOrCreateCallCount += 1
        guard !integrations.isEmpty else {
            let integration = GoogleIntegration()
            integrations = [integration]
            return integration
        }

        let current = integrations[min(index, integrations.count - 1)]
        if index < integrations.count - 1 {
            index += 1
        }
        return current
    }

    func save(_ integration: GoogleIntegration) async throws {
        if integrations.isEmpty {
            integrations = [integration]
            index = 0
        } else {
            integrations[min(index, integrations.count - 1)] = integration
        }
    }

    func update(_ integration: GoogleIntegration) async throws {
        try await save(integration)
    }

    func clearTokens(_ integration: GoogleIntegration) async throws {
        integration.refreshToken = nil
        integration.spreadsheetId = nil
        integration.googleUserId = nil
        integration.isEnabled = false
        try await save(integration)
    }
}
