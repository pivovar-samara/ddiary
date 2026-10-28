import XCTest
@testable import DDiary

@MainActor
final class GlucoseMeasurementKindTests: XCTestCase {
    func test_allCases_areEveryMealBeforeAndAfter_thenBedtime() {
        let pairs = GlucoseMeasurementKind.allCases.map { "\($0.mealSlot.rawValue).\($0.measurementType.rawValue)" }

        XCTAssertEqual(pairs, [
            "breakfast.beforeMeal", "breakfast.afterMeal2h",
            "lunch.beforeMeal", "lunch.afterMeal2h",
            "dinner.beforeMeal", "dinner.afterMeal2h",
            "none.bedtime",
        ])
    }

    func test_allCases_haveUniqueIdsAndTitles() {
        let cases = GlucoseMeasurementKind.allCases

        XCTAssertEqual(Set(cases.map(\.id)).count, cases.count)
        XCTAssertEqual(Set(cases.map(\.title)).count, cases.count)
    }

    func test_init_whenBedtimeWithMeal_dropsMeal() {
        let kind = GlucoseMeasurementKind(mealSlot: .dinner, measurementType: .bedtime)

        XCTAssertEqual(kind, .bedtime)
    }

    func test_init_whenMealTypeWithoutMeal_fallsBackToBreakfast() {
        let kind = GlucoseMeasurementKind(mealSlot: .none, measurementType: .afterMeal2h)

        XCTAssertEqual(kind.mealSlot, .breakfast)
        XCTAssertEqual(kind.measurementType, .afterMeal2h)
        XCTAssertTrue(GlucoseMeasurementKind.allCases.contains(kind))
    }

    func test_init_whenValidPair_keepsIt() {
        let kind = GlucoseMeasurementKind(mealSlot: .lunch, measurementType: .beforeMeal)

        XCTAssertEqual(kind.mealSlot, .lunch)
        XCTAssertEqual(kind.measurementType, .beforeMeal)
    }

    func test_plannedScheduledDate_whenTagUnchanged_keepsScheduleLink() {
        let planned = Date(timeIntervalSince1970: 1_000)
        let lunch = GlucoseMeasurementKind(mealSlot: .lunch, measurementType: .beforeMeal)

        XCTAssertEqual(
            GlucoseMeasurementKind.plannedScheduledDate(planned, original: lunch, selected: lunch),
            planned
        )
    }

    func test_plannedScheduledDate_whenTagChanged_dropsScheduleLink() {
        let planned = Date(timeIntervalSince1970: 1_000)
        let lunch = GlucoseMeasurementKind(mealSlot: .lunch, measurementType: .beforeMeal)
        let dinner = GlucoseMeasurementKind(mealSlot: .dinner, measurementType: .beforeMeal)

        XCTAssertNil(GlucoseMeasurementKind.plannedScheduledDate(planned, original: lunch, selected: dinner))
    }

    func test_plannedScheduledDate_whenManualEntry_staysUnlinked() {
        let lunch = GlucoseMeasurementKind(mealSlot: .lunch, measurementType: .beforeMeal)

        XCTAssertNil(GlucoseMeasurementKind.plannedScheduledDate(nil, original: lunch, selected: lunch))
    }
}
