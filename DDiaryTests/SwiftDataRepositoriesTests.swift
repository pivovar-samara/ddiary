import XCTest
import SwiftData
@testable import DDiary

@MainActor
final class SwiftDataMeasurementsRepositoryTests: XCTestCase {
    func test_bpCrud_rangeAndPendingFailedFiltering() async throws {
        let container = try makeInMemoryModelContainer()
        let repository = SwiftDataMeasurementsRepository(modelContext: ModelContext(container))

        let now = Date()
        let old = now.addingTimeInterval(-3600)
        let future = now.addingTimeInterval(3600)

        let bpOld = BPMeasurement(
            id: UUID(),
            timestamp: old,
            systolic: 120,
            diastolic: 80,
            pulse: 70,
            comment: "old",
            googleSyncStatus: .pending
        )
        let bpNow = BPMeasurement(
            id: UUID(),
            timestamp: now,
            systolic: 118,
            diastolic: 78,
            pulse: 69,
            comment: "now",
            googleSyncStatus: .success
        )
        let bpFuture = BPMeasurement(
            id: UUID(),
            timestamp: future,
            systolic: 130,
            diastolic: 85,
            pulse: 75,
            comment: "future",
            googleSyncStatus: .failed
        )

        try await repository.insertBP(bpFuture)
        try await repository.insertBP(bpOld)
        try await repository.insertBP(bpNow)

        let inRange = try await repository.bpMeasurements(from: old, to: now)
        XCTAssertEqual(inRange.map(\.id), [bpOld.id, bpNow.id])

        bpNow.comment = "updated"
        try await repository.updateBP(bpNow)
        let fetchedByID = try await repository.bpMeasurement(id: bpNow.id)
        XCTAssertEqual(fetchedByID?.comment, "updated")

        let pendingOrFailed = try await repository.pendingOrFailedBPSync()
        XCTAssertEqual(pendingOrFailed.map(\.id), [bpOld.id, bpFuture.id])

        try await repository.deleteBP(bpOld)
        let deletedBP = try await repository.bpMeasurement(id: bpOld.id)
        XCTAssertNil(deletedBP)
    }

    func test_glucoseCrud_rangeAndPendingFailedFiltering() async throws {
        let container = try makeInMemoryModelContainer()
        let repository = SwiftDataMeasurementsRepository(modelContext: ModelContext(container))

        let now = Date()
        let old = now.addingTimeInterval(-5400)
        let future = now.addingTimeInterval(7200)

        let gOld = GlucoseMeasurement(
            id: UUID(),
            timestamp: old,
            value: 5.4,
            unit: .mmolL,
            measurementType: .beforeMeal,
            mealSlot: .breakfast,
            comment: "old",
            googleSyncStatus: .pending
        )
        let gNow = GlucoseMeasurement(
            id: UUID(),
            timestamp: now,
            value: 6.0,
            unit: .mmolL,
            measurementType: .afterMeal2h,
            mealSlot: .lunch,
            comment: "now",
            googleSyncStatus: .success
        )
        let gFuture = GlucoseMeasurement(
            id: UUID(),
            timestamp: future,
            value: 7.1,
            unit: .mmolL,
            measurementType: .bedtime,
            mealSlot: .none,
            comment: "future",
            googleSyncStatus: .failed
        )

        try await repository.insertGlucose(gNow)
        try await repository.insertGlucose(gFuture)
        try await repository.insertGlucose(gOld)

        let inRange = try await repository.glucoseMeasurements(from: old, to: now)
        XCTAssertEqual(inRange.map(\.id), [gOld.id, gNow.id])

        gNow.value = 6.2
        try await repository.updateGlucose(gNow)
        let fetchedByID = try await repository.glucoseMeasurement(id: gNow.id)
        XCTAssertEqual(fetchedByID?.value, 6.2)

        let pendingOrFailed = try await repository.pendingOrFailedGlucoseSync()
        XCTAssertEqual(pendingOrFailed.map(\.id), [gOld.id, gFuture.id])

        try await repository.deleteGlucose(gOld)
        let deletedGlucose = try await repository.glucoseMeasurement(id: gOld.id)
        XCTAssertNil(deletedGlucose)
    }
}

@MainActor
final class SwiftDataSettingsRepositoryTests: XCTestCase {
    func test_getOrCreate_returnsPersistedSingleton() async throws {
        let container = try makeInMemoryModelContainer()
        let repository = SwiftDataSettingsRepository(modelContext: ModelContext(container))

        let first = try await repository.getOrCreate()
        let second = try await repository.getOrCreate()

        XCTAssertEqual(first.id, second.id)
    }

    func test_save_insertsDetachedSettingsAndUpdatePersistsChanges() async throws {
        let container = try makeInMemoryModelContainer()
        let repository = SwiftDataSettingsRepository(modelContext: ModelContext(container))

        let settings = UserSettings.default()
        settings.bpSystolicMax = 150
        settings.enableDailyCycleMode = true
        settings.currentCycleIndex = 2

        try await repository.save(settings)

        let stored = try await repository.getOrCreate()
        XCTAssertEqual(stored.id, settings.id)
        XCTAssertEqual(stored.bpSystolicMax, 150)
        XCTAssertTrue(stored.enableDailyCycleMode)
        XCTAssertEqual(stored.currentCycleIndex, 2)

        stored.bpSystolicMin = 95
        try await repository.update(stored)

        let refreshed = try await repository.getOrCreate()
        XCTAssertEqual(refreshed.bpSystolicMin, 95)
    }

    func test_getOrCreate_prefersMostCustomizedRecord_andDeletesDuplicates() async throws {
        let container = try makeInMemoryModelContainer()
        let context = ModelContext(container)
        let repository = SwiftDataSettingsRepository(modelContext: context)

        let placeholder = UserSettings.default()

        let customized = UserSettings.default()
        customized.enableDailyCycleMode = true
        customized.currentCycleIndex = 2
        customized.bedtimeSlotEnabled = true
        customized.bpTimes = [8 * 60, 13 * 60, 20 * 60]

        context.insert(placeholder)
        context.insert(customized)
        try context.save()

        let resolved = try await repository.getOrCreate()
        XCTAssertEqual(resolved.id, customized.id)
        XCTAssertTrue(resolved.enableDailyCycleMode)
        XCTAssertEqual(resolved.currentCycleIndex, 2)
        XCTAssertTrue(resolved.bedtimeSlotEnabled)
        XCTAssertEqual(resolved.bpTimes, [8 * 60, 13 * 60, 20 * 60])

        let all = try context.fetch(FetchDescriptor<UserSettings>())
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.id, customized.id)
    }

    func test_save_whenSingletonExists_updatesPrimaryWithoutInsertingDuplicate() async throws {
        let container = try makeInMemoryModelContainer()
        let context = ModelContext(container)
        let repository = SwiftDataSettingsRepository(modelContext: context)

        let primary = try await repository.getOrCreate()

        let detached = UserSettings.default()
        detached.id = UUID()
        detached.bpSystolicMax = 155
        detached.enableDailyCycleMode = true
        detached.currentCycleIndex = 3

        try await repository.save(detached)

        let all = try context.fetch(FetchDescriptor<UserSettings>())
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.id, primary.id)

        let stored = try await repository.getOrCreate()
        XCTAssertEqual(stored.bpSystolicMax, 155)
        XCTAssertTrue(stored.enableDailyCycleMode)
        XCTAssertEqual(stored.currentCycleIndex, 3)
    }
}

@MainActor
final class SwiftDataGoogleIntegrationRepositoryTests: XCTestCase {
    func test_getOrCreate_returnsPersistedSingleton() async throws {
        let container = try makeInMemoryModelContainer()
        let repository = SwiftDataGoogleIntegrationRepository(modelContext: ModelContext(container))

        let first = try await repository.getOrCreate()
        let second = try await repository.getOrCreate()

        XCTAssertEqual(first.id, second.id)
    }

    func test_save_updateAndClearTokens_persistExpectedState() async throws {
        let container = try makeInMemoryModelContainer()
        let repository = SwiftDataGoogleIntegrationRepository(modelContext: ModelContext(container))

        let integration = GoogleIntegration()
        integration.isEnabled = true
        integration.refreshToken = "rt"
        integration.spreadsheetId = "sheet"
        integration.googleUserId = "uid"

        try await repository.save(integration)

        let stored = try await repository.getOrCreate()
        XCTAssertEqual(stored.id, integration.id)
        XCTAssertTrue(stored.isEnabled)
        XCTAssertEqual(stored.refreshToken, "rt")
        XCTAssertEqual(stored.spreadsheetId, "sheet")
        XCTAssertEqual(stored.googleUserId, "uid")

        stored.spreadsheetId = "sheet-updated"
        try await repository.update(stored)
        let updated = try await repository.getOrCreate()
        XCTAssertEqual(updated.spreadsheetId, "sheet-updated")

        try await repository.clearTokens(stored)
        let cleared = try await repository.getOrCreate()
        XCTAssertFalse(cleared.isEnabled)
        XCTAssertNil(cleared.refreshToken)
        XCTAssertNil(cleared.spreadsheetId)
        XCTAssertNil(cleared.googleUserId)
    }

    func test_getOrCreate_prefersMostCompleteRecord_andDeletesDuplicates() async throws {
        let container = try makeInMemoryModelContainer()
        let context = ModelContext(container)
        let repository = SwiftDataGoogleIntegrationRepository(modelContext: context)

        let localPlaceholder = GoogleIntegration()

        let cloudSynced = GoogleIntegration()
        cloudSynced.isEnabled = true
        cloudSynced.refreshToken = "rt"
        cloudSynced.spreadsheetId = "sheet"
        cloudSynced.googleUserId = "uid"

        context.insert(localPlaceholder)
        context.insert(cloudSynced)
        try context.save()

        let resolved = try await repository.getOrCreate()
        XCTAssertEqual(resolved.id, cloudSynced.id)

        let all = try context.fetch(FetchDescriptor<GoogleIntegration>())
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.id, cloudSynced.id)
    }

    func test_getOrCreate_deletesDuplicates_evenWhenModelIDsMatch() async throws {
        let container = try makeInMemoryModelContainer()
        let context = ModelContext(container)
        let repository = SwiftDataGoogleIntegrationRepository(modelContext: context)

        let sharedID = UUID()
        let placeholder = GoogleIntegration()
        placeholder.id = sharedID

        let cloudSynced = GoogleIntegration()
        cloudSynced.id = sharedID
        cloudSynced.isEnabled = true
        cloudSynced.refreshToken = "rt"
        cloudSynced.spreadsheetId = "sheet"
        cloudSynced.googleUserId = "uid"

        context.insert(placeholder)
        context.insert(cloudSynced)
        try context.save()

        let resolved = try await repository.getOrCreate()
        XCTAssertEqual(resolved.id, sharedID)
        XCTAssertEqual(resolved.refreshToken, "rt")
        XCTAssertEqual(resolved.spreadsheetId, "sheet")
        XCTAssertTrue(resolved.isEnabled)

        let all = try context.fetch(FetchDescriptor<GoogleIntegration>())
        XCTAssertEqual(all.count, 1)
    }
}

@MainActor
private func makeInMemoryModelContainer() throws -> ModelContainer {
    try ModelContainer(
        for: Schema([
            BPMeasurement.self,
            GlucoseMeasurement.self,
            UserSettings.self,
            GoogleIntegration.self
        ]),
        configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
    )
}
