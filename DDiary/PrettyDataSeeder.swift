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
        switch true {
        case languageCode.hasPrefix("ru"):
            return LocalizedCopy(
                morningCheck: "Утреннее измерение",
                afterWalk: "После прогулки",
                busyDay: "Насыщенный день",
                eveningTired: "К вечеру немного устал",
                lightBreakfast: "Легкий завтрак",
                feltGoodMorning: "Утром самочувствие было хорошим",
                queuedForSync: "В очереди на синхронизацию"
            )
        case languageCode.hasPrefix("uk"):
            return LocalizedCopy(
                morningCheck: "Ранковий вимір",
                afterWalk: "Після прогулянки",
                busyDay: "Насичений день",
                eveningTired: "Увечері трохи втомився",
                lightBreakfast: "Легкий сніданок",
                feltGoodMorning: "Вранці самопочуття було добрим",
                queuedForSync: "В черзі на синхронізацію"
            )
        case languageCode.hasPrefix("de"):
            return LocalizedCopy(
                morningCheck: "Morgenmessung",
                afterWalk: "Nach dem Spaziergang",
                busyDay: "Stressiger Tag",
                eveningTired: "Abends etwas müde",
                lightBreakfast: "Leichtes Frühstück",
                feltGoodMorning: "Morgens gut gefühlt",
                queuedForSync: "Wartet auf Synchronisierung"
            )
        case languageCode.hasPrefix("es"):
            return LocalizedCopy(
                morningCheck: "Medición matutina",
                afterWalk: "Después de caminar",
                busyDay: "Día ajetreado",
                eveningTired: "Un poco cansado por la noche",
                lightBreakfast: "Desayuno ligero",
                feltGoodMorning: "Me sentí bien esta mañana",
                queuedForSync: "En cola para sincronizar"
            )
        case languageCode.hasPrefix("fr"):
            return LocalizedCopy(
                morningCheck: "Mesure du matin",
                afterWalk: "Après une promenade",
                busyDay: "Journée chargée",
                eveningTired: "Un peu fatigué le soir",
                lightBreakfast: "Petit-déjeuner léger",
                feltGoodMorning: "Je me suis senti bien ce matin",
                queuedForSync: "En attente de synchronisation"
            )
        case languageCode.hasPrefix("it"):
            return LocalizedCopy(
                morningCheck: "Misurazione mattutina",
                afterWalk: "Dopo una passeggiata",
                busyDay: "Giornata intensa",
                eveningTired: "Un po' stanco la sera",
                lightBreakfast: "Colazione leggera",
                feltGoodMorning: "Mi sono sentito bene stamattina",
                queuedForSync: "In coda per la sincronizzazione"
            )
        case languageCode.hasPrefix("pt"):
            return LocalizedCopy(
                morningCheck: "Medição matinal",
                afterWalk: "Após uma caminhada",
                busyDay: "Dia agitado",
                eveningTired: "Um pouco cansado à noite",
                lightBreakfast: "Café da manhã leve",
                feltGoodMorning: "Me senti bem esta manhã",
                queuedForSync: "Na fila para sincronizar"
            )
        case languageCode.hasPrefix("pl"):
            return LocalizedCopy(
                morningCheck: "Poranny pomiar",
                afterWalk: "Po spacerze",
                busyDay: "Pracowity dzień",
                eveningTired: "Wieczorem trochę zmęczony",
                lightBreakfast: "Lekkie śniadanie",
                feltGoodMorning: "Rano czułem się dobrze",
                queuedForSync: "W kolejce do synchronizacji"
            )
        case languageCode.hasPrefix("ar"):
            return LocalizedCopy(
                morningCheck: "قياس الصباح",
                afterWalk: "بعد المشي",
                busyDay: "يوم مشغول",
                eveningTired: "تعبت قليلاً في المساء",
                lightBreakfast: "إفطار خفيف",
                feltGoodMorning: "شعرت بتحسن هذا الصباح",
                queuedForSync: "في قائمة انتظار المزامنة"
            )
        case languageCode.hasPrefix("tr"):
            return LocalizedCopy(
                morningCheck: "Sabah ölçümü",
                afterWalk: "Yürüyüşten sonra",
                busyDay: "Yoğun gün",
                eveningTired: "Akşam biraz yorgun",
                lightBreakfast: "Hafif kahvaltı",
                feltGoodMorning: "Bu sabah kendimi iyi hissettim",
                queuedForSync: "Senkronizasyon kuyruğunda"
            )
        case languageCode.hasPrefix("sv"):
            return LocalizedCopy(
                morningCheck: "Morgonmätning",
                afterWalk: "Efter en promenad",
                busyDay: "Stressig dag",
                eveningTired: "Lite trött på kvällen",
                lightBreakfast: "Lätt frukost",
                feltGoodMorning: "Mådde bra i morse",
                queuedForSync: "Väntar på synkronisering"
            )
        case languageCode.hasPrefix("nl"):
            return LocalizedCopy(
                morningCheck: "Ochtendmeting",
                afterWalk: "Na een wandeling",
                busyDay: "Drukke dag",
                eveningTired: "Wat moe 's avonds",
                lightBreakfast: "Licht ontbijt",
                feltGoodMorning: "Voelde me goed vanochtend",
                queuedForSync: "Wacht op synchronisatie"
            )
        case languageCode.hasPrefix("ja"):
            return LocalizedCopy(
                morningCheck: "朝の測定",
                afterWalk: "散歩の後",
                busyDay: "忙しい一日",
                eveningTired: "夕方少し疲れた",
                lightBreakfast: "軽い朝食",
                feltGoodMorning: "今朝は体調が良かった",
                queuedForSync: "同期待ち"
            )
        case languageCode.hasPrefix("ko"):
            return LocalizedCopy(
                morningCheck: "아침 측정",
                afterWalk: "산책 후",
                busyDay: "바쁜 하루",
                eveningTired: "저녁에 좀 피곤함",
                lightBreakfast: "가벼운 아침 식사",
                feltGoodMorning: "오늘 아침 컨디션 좋음",
                queuedForSync: "동기화 대기 중"
            )
        case languageCode.hasPrefix("zh"):
            return LocalizedCopy(
                morningCheck: "早上测量",
                afterWalk: "散步后",
                busyDay: "忙碌的一天",
                eveningTired: "傍晚有些疲惫",
                lightBreakfast: "清淡早餐",
                feltGoodMorning: "今早感觉不错",
                queuedForSync: "等待同步"
            )
        default:
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
    }

    static func date(on base: Date, hour: Int, minute: Int, calendar: Calendar) -> Date {
        let startOfDay = calendar.startOfDay(for: base)
        return calendar.date(byAdding: DateComponents(hour: hour, minute: minute), to: startOfDay) ?? base
    }
}
