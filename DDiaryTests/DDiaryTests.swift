//
//  DDiaryTests.swift
//  DDiaryTests
//
//  Created by Ilia Khokhlov on 24.11.25.
//

import Testing
import SwiftData
import Foundation
@testable import DDiary

struct DDiaryTests {

    @Test("BPMeasurement save & fetch with in-memory ModelContainer")
    func testBPMeasurementSaveAndFetch() throws {
        // Build an in-memory SwiftData container with just the BPMeasurement model
        let schema = Schema([BPMeasurement.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        // Given: a BPMeasurement we want to persist
        let expectedId = UUID()
        let expectedTimestamp = Date(timeIntervalSince1970: 1_732_579_200) // Fixed date for determinism if needed
        let bp = BPMeasurement(
            id: expectedId,
            timestamp: expectedTimestamp,
            systolic: 120,
            diastolic: 80,
            pulse: 70,
            comment: "Test",
            googleSyncStatus: .notSynced
        )

        // When: insert and save
        context.insert(bp)
        try context.save()

        // Then: fetch it back by id and verify fields
        var descriptor = FetchDescriptor<BPMeasurement>(
            predicate: #Predicate { $0.id == expectedId }
        )
        descriptor.fetchLimit = 1
        let results = try context.fetch(descriptor)
        let fetched = try #require(results.first, "Expected to fetch the inserted BPMeasurement")

        #expect(fetched.id == expectedId)
        #expect(fetched.systolic == 120)
        #expect(fetched.diastolic == 80)
        #expect(fetched.pulse == 70)
        #expect(fetched.comment == "Test")
        #expect(fetched.googleSyncStatus == .notSynced)
    }

}
