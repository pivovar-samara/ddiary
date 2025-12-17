import Testing
import SwiftData
import Foundation
@testable import DDiary

@Suite("Models and SwiftData basic persistence")
struct ModelsPersistenceTests {
    @Test("Insert and fetch BPMeasurement")
    @MainActor
    func insertAndFetchBP() throws {
        let container = try ModelContainer(
            for: Schema([
                BPMeasurement.self,
                GlucoseMeasurement.self,
                UserSettings.self,
                GoogleIntegration.self,
            ]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)

        let bp = BPMeasurement(
            id: UUID(),
            timestamp: Date(),
            systolic: 120,
            diastolic: 80,
            pulse: 70,
            comment: "Test BP",
            googleSyncStatus: .pending,
            googleLastError: nil,
            googleLastSyncAt: nil
        )

        context.insert(bp)
        try context.save()

        let bpID = bp.id
        let descriptor = FetchDescriptor<BPMeasurement>(predicate: #Predicate { $0.id == bpID })
        let fetched = try context.fetch(descriptor)

        #expect(fetched.count == 1, "Exactly one BPMeasurement should be fetched")
        let item = try #require(fetched.first)
        #expect(item.systolic == 120)
        #expect(item.diastolic == 80)
        #expect(item.pulse == 70)
    }

    @Test("Insert and fetch GlucoseMeasurement")
    @MainActor
    func insertAndFetchGlucose() throws {
        let container = try ModelContainer(
            for: Schema([
                BPMeasurement.self,
                GlucoseMeasurement.self,
                UserSettings.self,
                GoogleIntegration.self,
            ]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)

        let g = GlucoseMeasurement(
            id: UUID(),
            timestamp: Date(),
            value: 5.6,
            unit: .mmolL,
            measurementType: .beforeMeal,
            mealSlot: .breakfast,
            comment: "Test Glucose",
            googleSyncStatus: .pending,
            googleLastError: nil,
            googleLastSyncAt: nil
        )

        context.insert(g)
        try context.save()

        let gID = g.id
        let descriptor = FetchDescriptor<GlucoseMeasurement>(predicate: #Predicate { $0.id == gID })
        let fetched = try context.fetch(descriptor)

        #expect(fetched.count == 1, "Exactly one GlucoseMeasurement should be fetched")
        let item = try #require(fetched.first)
        #expect(item.value == 5.6)
        #expect(item.unit == .mmolL)
        #expect(item.measurementType == .beforeMeal)
        #expect(item.mealSlot == .breakfast)
    }

    @Test("Create default UserSettings and fetch")
    @MainActor
    func createDefaultSettings() throws {
        let container = try ModelContainer(
            for: Schema([
                BPMeasurement.self,
                GlucoseMeasurement.self,
                UserSettings.self,
                GoogleIntegration.self,
            ]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)

        let settings = UserSettings.default()
        context.insert(settings)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<UserSettings>())
        #expect(fetched.count == 1, "There should be exactly one UserSettings instance")
        let s = try #require(fetched.first)
        #expect(s.glucoseUnit == .mmolL)
        #expect(s.bpTimes.isEmpty == false, "Default BP times should not be empty")
        #expect(s.bpActiveWeekdays.isEmpty == false, "Default active weekdays should not be empty")
    }
}
