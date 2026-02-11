//
//  ExportCSVUseCaseTests.swift
//  DDiary
//
//  Created by Ilia Khokhlov on 10.12.25.
//

import XCTest
@testable import DDiary

@MainActor
final class ExportCSVUseCaseTests: XCTestCase {
    func test_happyPath_writesFileWithHeaders() async throws {
        let repo = MockMeasurementsRepository()
        // Seed some data
        let bp = BPMeasurement(timestamp: Date(), systolic: 120, diastolic: 80, pulse: 70, comment: "ok")
        try await repo.insertBP(bp)
        let g = GlucoseMeasurement(timestamp: Date(), value: 5.6, unit: .mmolL, measurementType: .beforeMeal, mealSlot: .breakfast, comment: nil)
        try await repo.insertGlucose(g)

        let sut = ExportCSVUseCase(measurementsRepository: repo)
        let url = try await sut.exportCSV(from: Date.distantPast, to: Date.distantFuture, includeBP: true, includeGlucose: true)
        let data = try Data(contentsOf: url)
        let text = String(decoding: data, as: UTF8.self)
        let bpHeader = [
            L10n.exportHeaderTimestamp,
            L10n.exportHeaderDate,
            L10n.exportHeaderTime,
            L10n.exportHeaderSystolic,
            L10n.exportHeaderDiastolic,
            L10n.exportHeaderPulse,
            L10n.exportHeaderComment,
            L10n.exportHeaderId
        ].joined(separator: ",")
        let glucoseHeader = [
            L10n.exportHeaderTimestamp,
            L10n.exportHeaderDate,
            L10n.exportHeaderTime,
            L10n.exportHeaderValue,
            L10n.exportHeaderUnit,
            L10n.exportHeaderMeasurementType,
            L10n.exportHeaderMealSlot,
            L10n.exportHeaderComment,
            L10n.exportHeaderId
        ].joined(separator: ",")
        XCTAssertTrue(text.contains(bpHeader))
        XCTAssertTrue(text.contains(glucoseHeader))
    }
}
