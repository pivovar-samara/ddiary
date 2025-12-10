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
        XCTAssertTrue(text.contains("timestamp,date,time,systolic,diastolic,pulse,comment,id"))
        XCTAssertTrue(text.contains("timestamp,date,time,value,unit,measurementType,mealSlot,comment,id"))
    }
}
