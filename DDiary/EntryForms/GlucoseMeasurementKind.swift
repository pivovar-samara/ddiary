//
//  GlucoseMeasurementKind.swift
//  DDiary
//

import Foundation

/// A valid meal-tag pair for a glucose measurement: one of the three meals before or after eating,
/// or bedtime. These are exactly the pairs `GetTodayOverviewUseCase` can plan, so every option the
/// entry form offers can match a slot. Settings do not narrow the list: a pair the schedule skips is
/// still a valid tag for a manual entry.
public struct GlucoseMeasurementKind: Hashable, Sendable, Identifiable {
    public let mealSlot: MealSlot
    public let measurementType: GlucoseMeasurementType

    public static let bedtime = GlucoseMeasurementKind(uncheckedMealSlot: .none, measurementType: .bedtime)

    public static let allCases: [GlucoseMeasurementKind] = [MealSlot.breakfast, .lunch, .dinner]
        .flatMap { meal in
            [GlucoseMeasurementType.beforeMeal, .afterMeal2h].map {
                GlucoseMeasurementKind(uncheckedMealSlot: meal, measurementType: $0)
            }
        } + [bedtime]

    /// Normalizes any stored pair to a valid one. Bedtime ignores the meal; a meal type without a meal
    /// (legacy or malformed data) falls back to breakfast so the picker always has a selection.
    public init(mealSlot: MealSlot, measurementType: GlucoseMeasurementType) {
        switch (measurementType, mealSlot) {
        case (.bedtime, _):
            self = .bedtime
        case (_, .none):
            self.init(uncheckedMealSlot: .breakfast, measurementType: measurementType)
        default:
            self.init(uncheckedMealSlot: mealSlot, measurementType: measurementType)
        }
    }

    private init(uncheckedMealSlot: MealSlot, measurementType: GlucoseMeasurementType) {
        self.mealSlot = uncheckedMealSlot
        self.measurementType = measurementType
    }

    public var id: String { "\(mealSlot.rawValue).\(measurementType.rawValue)" }

    var title: String {
        UIStrings.glucoseTitle(mealSlot: mealSlot.rawValue, measurementType: measurementType.rawValue)
    }

    /// The planned date to save with a new measurement. A measurement keeps its schedule link only
    /// while it carries the tag of the slot it was opened from; retagged, it is a manual entry, so it
    /// neither completes a slot it was not planned for nor cancels that slot's reminder.
    static func plannedScheduledDate(
        _ plannedScheduledDate: Date?,
        original: GlucoseMeasurementKind?,
        selected: GlucoseMeasurementKind
    ) -> Date? {
        selected == original ? plannedScheduledDate : nil
    }
}
