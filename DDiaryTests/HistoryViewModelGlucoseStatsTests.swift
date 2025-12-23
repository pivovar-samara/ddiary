//
//  HistoryViewModelGlucoseStatsTests.swift
//  DDiary
//
//  Created by Ilia Khokhlov on 23.12.25.
//

import Testing
import Foundation
@testable import DDiary

@Suite("HistoryViewModel Glucose Stats")
struct HistoryViewModelGlucoseStatsTests {

    @Test("Min/Max/Avg computed for valid glucose values")
    @MainActor
    func testGlucoseStatsComputation() async throws {
        // Arrange: Build a VM with a stub getHistory use case returning 3 glucose measurements
        let repo = InMemoryMeasurementsRepository()
        try await repo.insertGlucose(GlucoseMeasurement(
            id: UUID(), timestamp: Date(), value: 21, unit: .mmolL, measurementType: .beforeMeal, mealSlot: .breakfast, comment: nil
        ))
        try await repo.insertGlucose(GlucoseMeasurement(
            id: UUID(), timestamp: Date(), value: 22, unit: .mmolL, measurementType: .beforeMeal, mealSlot: .lunch, comment: nil
        ))
        try await repo.insertGlucose(GlucoseMeasurement(
            id: UUID(), timestamp: Date(), value: 55, unit: .mmolL, measurementType: .beforeMeal, mealSlot: .dinner, comment: nil
        ))

        let useCase = GetHistoryUseCase(measurementsRepository: repo)
        let vm = HistoryViewModel(getHistory: useCase, initialRange: HistoryViewModel.defaultRange(.days7))
        vm.selectedFilter = .glucose

        // Act
        await vm.loadHistory()

        // Assert
        #expect(vm.glucoseMin == 21)
        #expect(vm.glucoseMax == 55)
        let avg = try #require(vm.glucoseAvg)
        // Rounded to two decimals should be 32.67
        let rounded = (avg * 100).rounded() / 100
        #expect(rounded == 32.67)
    }
}

// Minimal in-memory repo for testing on @MainActor
@MainActor
final class InMemoryMeasurementsRepository: MeasurementsRepository {
    private var bp: [BPMeasurement] = []
    private var gl: [GlucoseMeasurement] = []

    func insertBP(_ measurement: BPMeasurement) async throws { bp.append(measurement) }
    func updateBP(_ measurement: BPMeasurement) async throws {}
    func deleteBP(_ measurement: BPMeasurement) async throws { bp.removeAll { $0.id == measurement.id } }
    func bpMeasurement(id: UUID) async throws -> BPMeasurement? { bp.first { $0.id == id } }
    func bpMeasurements(from: Date, to: Date) async throws -> [BPMeasurement] { bp }
    func pendingOrFailedBPSync() async throws -> [BPMeasurement] { [] }

    func insertGlucose(_ measurement: GlucoseMeasurement) async throws { gl.append(measurement) }
    func updateGlucose(_ measurement: GlucoseMeasurement) async throws {}
    func deleteGlucose(_ measurement: GlucoseMeasurement) async throws { gl.removeAll { $0.id == measurement.id } }
    func glucoseMeasurement(id: UUID) async throws -> GlucoseMeasurement? { gl.first { $0.id == id } }
    func glucoseMeasurements(from: Date, to: Date) async throws -> [GlucoseMeasurement] { gl }
    func pendingOrFailedGlucoseSync() async throws -> [GlucoseMeasurement] { [] }
}

