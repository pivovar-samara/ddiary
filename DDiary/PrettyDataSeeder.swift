import Foundation
import SwiftData

enum PrettyDataScenario: String {
    case showcase
}

@MainActor
enum PrettyDataSeeder {
    static func seed(
        _ scenario: PrettyDataScenario = .showcase,
        into modelContainer: ModelContainer,
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .autoupdatingCurrent
    ) throws {
        let context = ModelContext(modelContainer)
        try clearExistingData(context: context)

        switch scenario {
        case .showcase:
            try seedShowcase(context: context, now: now, calendar: calendar, locale: locale)
        }

        try context.save()
    }
}

private extension PrettyDataSeeder {
    struct LocalizedCopy {
        let morningCheck: String
        let afterWalk: String
        let busyDay: String
        let eveningTired: String
        let lightBreakfast: String
        let feltGoodMorning: String
        let queuedForSync: String
    }

    static func clearExistingData(context: ModelContext) throws {
        try context.fetch(FetchDescriptor<BPMeasurement>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<GlucoseMeasurement>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<UserSettings>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<GoogleIntegration>()).forEach(context.delete)
    }

    static func seedShowcase(
        context: ModelContext,
        now: Date,
        calendar: Calendar,
        locale: Locale
    ) throws {
        let startOfToday = calendar.startOfDay(for: now)
        let copy = localizedCopy(for: locale)

        let settings = UserSettings.default()
        settings.glucoseUnit = .mmolL
        settings.bpSystolicMin = 95
        settings.bpSystolicMax = 135
        settings.bpDiastolicMin = 65
        settings.bpDiastolicMax = 85
        settings.glucoseMin = 4.4
        settings.glucoseMax = 7.8
        settings.breakfastHour = 8
        settings.breakfastMinute = 0
        settings.lunchHour = 13
        settings.lunchMinute = 0
        settings.dinnerHour = 19
        settings.dinnerMinute = 0
        settings.bedtimeSlotEnabled = true
        settings.bedtimeHour = 22
        settings.bedtimeMinute = 30
        settings.bpTimes = [8 * 60 + 30, 21 * 60]
        settings.bpActiveWeekdays = Set(1...7)
        settings.enableBeforeMeal = true
        settings.enableAfterMeal2h = true
        settings.enableDailyCycleMode = false
        settings.dailyCycleAnchorDate = nil
        settings.cycleOverrides = [:]
        context.insert(settings)

        let integration = GoogleIntegration(
            spreadsheetId: "demo-showcase-backup",
            googleUserId: "demo.user@gmail.com",
            isEnabled: true
        )
        context.insert(integration)

        let bpSeedValues: [(sys: Int, dia: Int, pulse: Int, comment: String?)] = [
            (124, 78, 69, copy.morningCheck),
            (129, 81, 72, nil),
            (121, 76, 68, copy.afterWalk),
            (127, 80, 71, nil),
            (123, 77, 67, nil),
            (130, 82, 73, copy.busyDay),
            (122, 78, 70, nil),
        ]

        let glucoseSeedValues: [(before: Double, after: Double, dinnerBefore: Double?, dinnerAfter: Double?, bedtime: Double?)] = [
            (5.4, 6.8, 5.9, 7.2, 6.1),
            (5.7, 7.0, 6.0, 7.4, nil),
            (5.3, 6.7, nil, 7.1, 5.9),
            (5.6, 6.9, 6.1, nil, 6.2),
            (5.2, 6.6, 5.8, 7.0, nil),
            (5.8, 7.3, 6.2, 7.6, 6.4),
            (5.5, 6.9, 6.0, 7.2, 6.0),
        ]

        for dayOffset in stride(from: 13, through: 1, by: -1) {
            let day = calendar.date(byAdding: .day, value: -dayOffset, to: startOfToday) ?? startOfToday
            let dayIndex = dayOffset % bpSeedValues.count
            let bpPreset = bpSeedValues[dayIndex]
            let glucosePreset = glucoseSeedValues[dayIndex]

            context.insert(
                BPMeasurement(
                    timestamp: date(on: day, hour: 8, minute: 28, calendar: calendar),
                    systolic: bpPreset.sys,
                    diastolic: bpPreset.dia,
                    pulse: bpPreset.pulse,
                    comment: bpPreset.comment,
                    isLinkedToSchedule: true,
                    googleSyncStatus: .success,
                    googleLastSyncAt: date(on: day, hour: 8, minute: 35, calendar: calendar)
                )
            )

            if dayOffset % 2 == 0 {
                context.insert(
                    BPMeasurement(
                        timestamp: date(on: day, hour: 21, minute: 4, calendar: calendar),
                        systolic: bpPreset.sys + 3,
                        diastolic: bpPreset.dia + 2,
                        pulse: bpPreset.pulse + 3,
                        comment: dayOffset == 4 ? copy.eveningTired : nil,
                        isLinkedToSchedule: true,
                        googleSyncStatus: .success,
                        googleLastSyncAt: date(on: day, hour: 21, minute: 10, calendar: calendar)
                    )
                )
            }

            context.insert(
                GlucoseMeasurement(
                    timestamp: date(on: day, hour: 7, minute: 54, calendar: calendar),
                    value: glucosePreset.before,
                    unit: .mmolL,
                    measurementType: .beforeMeal,
                    mealSlot: .breakfast,
                    comment: dayOffset == 5 ? copy.lightBreakfast : nil,
                    isLinkedToSchedule: true,
                    googleSyncStatus: .success,
                    googleLastSyncAt: date(on: day, hour: 8, minute: 3, calendar: calendar)
                )
            )

            context.insert(
                GlucoseMeasurement(
                    timestamp: date(on: day, hour: 10, minute: 2, calendar: calendar),
                    value: glucosePreset.after,
                    unit: .mmolL,
                    measurementType: .afterMeal2h,
                    mealSlot: .breakfast,
                    comment: nil,
                    isLinkedToSchedule: true,
                    googleSyncStatus: .success,
                    googleLastSyncAt: date(on: day, hour: 10, minute: 7, calendar: calendar)
                )
            )

            if let dinnerBefore = glucosePreset.dinnerBefore {
                context.insert(
                    GlucoseMeasurement(
                        timestamp: date(on: day, hour: 18, minute: 52, calendar: calendar),
                        value: dinnerBefore,
                        unit: .mmolL,
                        measurementType: .beforeMeal,
                        mealSlot: .dinner,
                        comment: nil,
                        isLinkedToSchedule: true,
                        googleSyncStatus: .success,
                        googleLastSyncAt: date(on: day, hour: 19, minute: 1, calendar: calendar)
                    )
                )
            }

            if let dinnerAfter = glucosePreset.dinnerAfter {
                context.insert(
                    GlucoseMeasurement(
                        timestamp: date(on: day, hour: 20, minute: 58, calendar: calendar),
                        value: dinnerAfter,
                        unit: .mmolL,
                        measurementType: .afterMeal2h,
                        mealSlot: .dinner,
                        comment: nil,
                        isLinkedToSchedule: true,
                        googleSyncStatus: .success,
                        googleLastSyncAt: date(on: day, hour: 21, minute: 4, calendar: calendar)
                    )
                )
            }

            if let bedtime = glucosePreset.bedtime {
                context.insert(
                    GlucoseMeasurement(
                        timestamp: date(on: day, hour: 22, minute: 24, calendar: calendar),
                        value: bedtime,
                        unit: .mmolL,
                        measurementType: .bedtime,
                        mealSlot: .none,
                        comment: nil,
                        isLinkedToSchedule: true,
                        googleSyncStatus: .success,
                        googleLastSyncAt: date(on: day, hour: 22, minute: 29, calendar: calendar)
                    )
                )
            }
        }

        context.insert(
            BPMeasurement(
                timestamp: date(on: startOfToday, hour: 8, minute: 27, calendar: calendar),
                systolic: 126,
                diastolic: 79,
                pulse: 70,
                comment: copy.feltGoodMorning,
                isLinkedToSchedule: true,
                googleSyncStatus: .success,
                googleLastSyncAt: date(on: startOfToday, hour: 8, minute: 33, calendar: calendar)
            )
        )

        context.insert(
            GlucoseMeasurement(
                timestamp: date(on: startOfToday, hour: 7, minute: 56, calendar: calendar),
                value: 5.6,
                unit: .mmolL,
                measurementType: .beforeMeal,
                mealSlot: .breakfast,
                comment: nil,
                isLinkedToSchedule: true,
                googleSyncStatus: .success,
                googleLastSyncAt: date(on: startOfToday, hour: 8, minute: 2, calendar: calendar)
            )
        )

        context.insert(
            BPMeasurement(
                timestamp: date(on: calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday, hour: 21, minute: 3, calendar: calendar),
                systolic: 131,
                diastolic: 83,
                pulse: 74,
                comment: copy.queuedForSync,
                isLinkedToSchedule: true,
                googleSyncStatus: .pending
            )
        )
    }

    static func localizedCopy(for locale: Locale) -> LocalizedCopy {
        let languageCode = locale.language.languageCode?.identifier ?? locale.identifier
        if languageCode.hasPrefix("ru") {
            return LocalizedCopy(
                morningCheck: "Утреннее измерение",
                afterWalk: "После прогулки",
                busyDay: "Насыщенный день",
                eveningTired: "К вечеру немного устал",
                lightBreakfast: "Легкий завтрак",
                feltGoodMorning: "Утром самочувствие было хорошим",
                queuedForSync: "В очереди на синхронизацию"
            )
        }

        return LocalizedCopy(
            morningCheck: "Morning check",
            afterWalk: "After a walk",
            busyDay: "Busy day",
            eveningTired: "A bit tired in the evening",
            lightBreakfast: "Light breakfast",
            feltGoodMorning: "Felt good this morning",
            queuedForSync: "Queued for sync"
        )
    }

    static func date(on base: Date, hour: Int, minute: Int, calendar: Calendar) -> Date {
        let startOfDay = calendar.startOfDay(for: base)
        return calendar.date(byAdding: DateComponents(hour: hour, minute: minute), to: startOfDay) ?? base
    }
}
