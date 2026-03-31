import SwiftData
import XCTest
@testable import DDiary

@MainActor
final class PrettyDataSeederTests: XCTestCase {
    func test_seedShowcase_createsPrettyDataPack() throws {
        let container = try makeInMemoryModelContainer()

        try PrettyDataSeeder.seed(.showcase, into: container, now: referenceNow)

        let context = ModelContext(container)
        let settings = try XCTUnwrap(try context.fetch(FetchDescriptor<UserSettings>()).first)
        let integration = try XCTUnwrap(try context.fetch(FetchDescriptor<GoogleIntegration>()).first)
        let bpMeasurements = try context.fetch(FetchDescriptor<BPMeasurement>())
        let glucoseMeasurements = try context.fetch(FetchDescriptor<GlucoseMeasurement>())

        XCTAssertEqual(settings.glucoseUnit, .mmolL)
        XCTAssertTrue(settings.bedtimeSlotEnabled)
        XCTAssertEqual(settings.bpTimes, [510, 1260])
        XCTAssertEqual(integration.googleUserId, "demo.user@gmail.com")
        XCTAssertTrue(integration.isEnabled)
        XCTAssertGreaterThanOrEqual(bpMeasurements.count, 10)
        XCTAssertGreaterThanOrEqual(glucoseMeasurements.count, 20)
        XCTAssertTrue(bpMeasurements.contains(where: { $0.googleSyncStatus == .pending }))
        XCTAssertFalse(glucoseMeasurements.contains(where: { $0.googleSyncStatus == .failed }))
        XCTAssertTrue(bpMeasurements.contains(where: { $0.comment == "Morning check" }))
    }

    func test_seedShowcase_usesRussianComments_whenLocaleIsRussian() throws {
        let container = try makeInMemoryModelContainer()

        try PrettyDataSeeder.seed(
            .showcase,
            into: container,
            now: referenceNow,
            locale: Locale(identifier: "ru_RU")
        )

        let context = ModelContext(container)
        let bpMeasurements = try context.fetch(FetchDescriptor<BPMeasurement>())

        XCTAssertTrue(bpMeasurements.contains(where: { $0.comment == "Утреннее измерение" }))
        XCTAssertTrue(bpMeasurements.contains(where: { $0.comment == "В очереди на синхронизацию" }))
        XCTAssertFalse(bpMeasurements.contains(where: { $0.comment == "Morning check" }))
    }

    private var referenceNow: Date {
        let calendar = Calendar(identifier: .gregorian)
        return calendar.date(from: DateComponents(year: 2026, month: 3, day: 30, hour: 14, minute: 0))!
    }

    private func makeInMemoryModelContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema([
                BPMeasurement.self,
                GlucoseMeasurement.self,
                UserSettings.self,
                GoogleIntegration.self,
            ]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)]
        )
    }
}
