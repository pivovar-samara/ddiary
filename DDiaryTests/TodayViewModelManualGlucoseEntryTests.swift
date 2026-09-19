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

    /// The schedule read is a real suspension point, so a slot tap or a notification can present its own
    /// entry while it is in flight. The manual intent must stand down rather than replace the selection:
    /// the view pairs its own `selectedGlucoseScheduledDate` with whatever slot is selected, so a stale
    /// manual tag would be saved as schedule-linked under the newer intent's planned date.
    func test_prepareManualGlucoseQuickEntry_whenAnotherEntryIsPresentedDuringTheRead_standsDown() async throws {
        let settings = GatedSettingsRepository()
        let userSettings = try await settings.configure()
        userSettings.enableDailyCycleMode = false
        userSettings.enableBeforeMeal = true
        userSettings.bedtimeSlotEnabled = true
        userSettings.bedtimeHour = 22
        userSettings.bedtimeMinute = 0

        let viewModel = makeViewModel(settings: settings)
        let scheduledSlot = GlucoseSlotViewModel(
            mealSlot: .breakfast,
            measurementType: .beforeMeal,
            displayTime: "08:00",
            scheduledDate: try date(year: 2026, month: 2, day: 17, hour: 8, minute: 0),
            status: .due,
            matchedMeasurementId: nil
        )

        let reference = try date(year: 2026, month: 2, day: 17, hour: 0, minute: 30)
        let preparing = Task { await viewModel.prepareManualGlucoseQuickEntry(referenceDate: reference) }
        try await settings.waitUntilSuspended()

        // A scheduled-slot tap wins the sheet while the manual intent is still suspended.
        viewModel.onGlucoseSlotTapped(scheduledSlot)
        settings.resume()
        await preparing.value

        XCTAssertEqual(viewModel.selectedGlucoseSlot, scheduledSlot)
        XCTAssertTrue(viewModel.presentGlucoseQuickEntry)
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


/// Suspends inside `getOrCreate()` until the test resumes it, so the window around the `await` in
/// `prepareManualGlucoseQuickEntry` can be driven deterministically.
@MainActor
private final class GatedSettingsRepository: SettingsRepository {
    private let inner = MockSettingsRepository()
    private var continuation: CheckedContinuation<Void, Never>?
    private var isSuspended = false

    /// Materializes the underlying settings so the test can set them up before the gated call.
    func configure() async throws -> UserSettings {
        try await inner.getOrCreate()
    }

    func waitUntilSuspended(iterations: Int = 1_000) async throws {
        for _ in 0..<iterations {
            if isSuspended { return }
            await Task.yield()
        }
        throw TestError.forced
    }

    func resume() {
        continuation?.resume()
        continuation = nil
        isSuspended = false
    }

    func getOrCreate() async throws -> UserSettings {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            self.isSuspended = true
        }
        return try await inner.getOrCreate()
    }

    func save(_ settings: UserSettings) async throws { try await inner.save(settings) }
    func update(_ settings: UserSettings) async throws { try await inner.update(settings) }
}
