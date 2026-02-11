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

    private func makeSUT(
        settingsRepository: SpySettingsRepository,
        measurementsRepository: MockMeasurementsRepository,
        schedulesUpdater: SpySchedulesUpdater
    ) -> SettingsViewModel {
        SettingsViewModel(
            settingsRepository: settingsRepository,
            googleIntegrationRepository: MockGoogleIntegrationRepository(),
            exportCSVUseCase: ExportCSVUseCase(measurementsRepository: measurementsRepository),
            measurementsRepository: measurementsRepository,
            googleSheetsClient: RecordingGoogleSheetsClient(),
            schedulesUpdater: schedulesUpdater
        )
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
