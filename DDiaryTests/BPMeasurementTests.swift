import XCTest
import SwiftData
@testable import DDiary

final class BPMeasurementTests: XCTestCase {

    @MainActor
    func testInsertAndFetchBPMeasurement() async throws {
        // Set up an in-memory SwiftData container
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Schema([
                BPMeasurement.self,
                GlucoseMeasurement.self,
                UserSettings.self,
                GoogleIntegration.self
            ]),
            configurations: config
        )
        let context = ModelContext(container)

        // Prepare expected values
        let expectedSystolic = 123
        let expectedDiastolic = 77
        let expectedPulse = 65
        let expectedComment = "Unit Test"
        let timestamp = Date()

        // Create and insert a BPMeasurement
        let measurement = BPMeasurement(
            timestamp: timestamp,
            systolic: expectedSystolic,
            diastolic: expectedDiastolic,
            pulse: expectedPulse,
            comment: expectedComment
        )

        context.insert(measurement)
        try context.save()

        // Fetch back by id
        let measurementID = measurement.id
        let descriptor = FetchDescriptor<BPMeasurement>(
            predicate: #Predicate { $0.id == measurementID }
        )
        let results = try context.fetch(descriptor)

        XCTAssertEqual(results.count, 1, "Exactly one measurement should be fetched.")
        guard let fetched = results.first else {
            XCTFail("No measurement fetched")
            return
        }

        // Verify fields
        XCTAssertEqual(fetched.id, measurement.id)
        XCTAssertEqual(fetched.systolic, expectedSystolic)
        XCTAssertEqual(fetched.diastolic, expectedDiastolic)
        XCTAssertEqual(fetched.pulse, expectedPulse)
        XCTAssertEqual(fetched.comment, expectedComment)
        XCTAssertEqual(fetched.googleSyncStatus, .pending)

        // Timestamps may differ slightly; ensure they are very close
        XCTAssertLessThan(abs(fetched.timestamp.timeIntervalSince(timestamp)), 1.0)
    }
}
