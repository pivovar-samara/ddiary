import XCTest
@testable import DDiary

/// Covers `TodayViewModel.prepareManualGlucoseQuickEntry(referenceDate:)` — the "+" → "Glucose" path.
/// None of these call `refresh()` first: that is the point, the derived tag no longer depends on the
/// already-loaded `glucoseSlots` of the current day.
@MainActor
final class TodayViewModelManualGlucoseEntryTests: XCTestCase {

    func test_prepareManualGlucoseQuickEntry_afterMidnight_selectsYesterdayBedtimeTag() async throws {
        let settings = MockSettingsRepository()
        let userSettings = try await settings.getOrCreate()
        userSettings.enableDailyCycleMode = false
        userSettings.enableBeforeMeal = true
        userSettings.enableAfterMeal2h = true
        userSettings.breakfastHour = 8
        userSettings.breakfastMinute = 0
        userSettings.bedtimeSlotEnabled = true
        userSettings.bedtimeHour = 22
        userSettings.bedtimeMinute = 0

        let viewModel = makeViewModel(settings: settings)
        let reference = try date(year: 2026, month: 2, day: 17, hour: 0, minute: 30)

        await viewModel.prepareManualGlucoseQuickEntry(referenceDate: reference)

        let selected = try XCTUnwrap(viewModel.selectedGlucoseSlot)
        XCTAssertEqual(selected.mealSlot, .none)
        XCTAssertEqual(selected.measurementType, .bedtime)
        XCTAssertEqual(selected.scheduledDate, try date(year: 2026, month: 2, day: 16, hour: 22, minute: 0))
        XCTAssertNil(selected.matchedMeasurementId)
        XCTAssertTrue(viewModel.presentGlucoseQuickEntry)
        XCTAssertFalse(viewModel.presentBPQuickEntry)
    }

    func test_prepareManualGlucoseQuickEntry_whenNoSlotsConfigured_fallsBackToBedtimeAtReferenceDate() async throws {
        let settings = MockSettingsRepository()
        let userSettings = try await settings.getOrCreate()
        userSettings.enableDailyCycleMode = false
        userSettings.enableBeforeMeal = false
        userSettings.enableAfterMeal2h = false
        userSettings.bedtimeSlotEnabled = false

        let viewModel = makeViewModel(settings: settings)
        let reference = try date(year: 2026, month: 2, day: 17, hour: 0, minute: 30)

        await viewModel.prepareManualGlucoseQuickEntry(referenceDate: reference)

        let selected = try XCTUnwrap(viewModel.selectedGlucoseSlot)
        XCTAssertEqual(selected.mealSlot, .none)
        XCTAssertEqual(selected.measurementType, .bedtime)
        XCTAssertEqual(selected.scheduledDate, reference)
        XCTAssertTrue(viewModel.presentGlucoseQuickEntry)
    }

    func test_prepareManualGlucoseQuickEntry_whenAlreadyPresented_doesNotReplaceSelection() async throws {
        let settings = MockSettingsRepository()
        let userSettings = try await settings.getOrCreate()
        userSettings.enableDailyCycleMode = false
        userSettings.enableBeforeMeal = true
        userSettings.bedtimeSlotEnabled = true
        userSettings.bedtimeHour = 22
        userSettings.bedtimeMinute = 0

        let viewModel = makeViewModel(settings: settings)
        let sentinel = GlucoseSlotViewModel(
            mealSlot: .lunch,
            measurementType: .beforeMeal,
            displayTime: "13:00",
            scheduledDate: try date(year: 2026, month: 2, day: 17, hour: 13, minute: 0),
            status: .due,
            matchedMeasurementId: nil
        )
        viewModel.selectedGlucoseSlot = sentinel
        viewModel.presentGlucoseQuickEntry = true

        await viewModel.prepareManualGlucoseQuickEntry(
            referenceDate: try date(year: 2026, month: 2, day: 17, hour: 0, minute: 30)
        )

        XCTAssertEqual(viewModel.selectedGlucoseSlot, sentinel)
    }

    func test_prepareManualGlucoseQuickEntry_whenSettingsCannotBeRead_reportsErrorAndKeepsSheetClosed() async throws {
        let viewModel = makeViewModel(settings: ThrowingSettingsRepository())

        await viewModel.prepareManualGlucoseQuickEntry(
            referenceDate: try date(year: 2026, month: 2, day: 17, hour: 0, minute: 30)
        )

        // No guessed tag: the form stays closed rather than defaulting to bedtime.
        XCTAssertFalse(viewModel.presentGlucoseQuickEntry)
        XCTAssertNil(viewModel.selectedGlucoseSlot)
        XCTAssertEqual(viewModel.errorMessage, L10n.todayErrorManualEntryUnavailable)
    }

    // MARK: - Helpers

    private func makeViewModel(settings: any SettingsRepository) -> TodayViewModel {
        let measurements = MockMeasurementsRepository()
        let analytics = MockAnalyticsRepository()
        return TodayViewModel(
            getTodayOverviewUseCase: GetTodayOverviewUseCase(
                measurementsRepository: measurements,
                settingsRepository: settings
            ),
            logBPMeasurementUseCase: LogBPMeasurementUseCase(
                measurementsRepository: measurements,
                analyticsRepository: analytics
            ),
            logGlucoseMeasurementUseCase: LogGlucoseMeasurementUseCase(
                measurementsRepository: measurements,
                settingsRepository: settings,
                analyticsRepository: analytics
            ),
            rescheduleGlucoseCycleUseCase: RescheduleGlucoseCycleUseCase(
                settingsRepository: settings,
                analyticsRepository: analytics
            ),
            schedulesUpdater: NoopSchedulesUpdater(),
            notificationsRepository: SilentNotificationsRepository()
        )
    }

    private func date(year: Int, month: Int, day: Int, hour: Int, minute: Int) throws -> Date {
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        return try XCTUnwrap(Calendar.current.date(from: components))
    }
}

@MainActor
private final class NoopSchedulesUpdater: SchedulesUpdating {
    func scheduleFromCurrentSettings() async throws {}
}

@MainActor
private final class ThrowingSettingsRepository: SettingsRepository {
    func getOrCreate() async throws -> UserSettings { throw TestError.forced }
    func save(_ settings: UserSettings) async throws { throw TestError.forced }
    func update(_ settings: UserSettings) async throws { throw TestError.forced }
}
