import XCTest
import UserNotifications
@testable import DDiary

@MainActor
final class UserNotificationsRepositoryTests: XCTestCase {
    func test_parseAction_treatsDefaultTapAsEnter() {
        XCTAssertEqual(
            UserNotificationsRepository.parseAction(actionIdentifier: UNNotificationDefaultActionIdentifier),
            .enter
        )
        XCTAssertEqual(
            UserNotificationsRepository.parseAction(actionIdentifier: UserNotificationsRepository.IDs.enterAction),
            .enter
        )
    }

    func test_registerCategories_setsAllExpectedCategories() {
        let center = FakeNotificationCenter()

        UserNotificationsRepository.registerCategories(center: center)

        let identifiers = Set(center.categories.map(\.identifier))
        XCTAssertEqual(identifiers, Set([
            UserNotificationsRepository.IDs.bpCategory,
            UserNotificationsRepository.IDs.glucoseBeforeCategory,
            UserNotificationsRepository.IDs.glucoseAfterCategory,
            UserNotificationsRepository.IDs.glucoseBedtimeCategory
        ]))
    }

    func test_scheduleBloodPressure_createsRequestsForEachWeekdayAndTime() async throws {
        let center = FakeNotificationCenter()
        let calendar = Calendar.current
        let referenceNow = calendar.date(
            from: DateComponents(year: 2026, month: 2, day: 16, hour: 7, minute: 30)
        ) ?? Date()
        let repository = UserNotificationsRepository(
            center: center,
            calendar: calendar,
            now: { referenceNow },
            schedulingWindowDays: 4
        )

        try await repository.scheduleBloodPressure(times: [540, 1260], activeWeekdays: [2, 4])

        let ids = Set(center.pendingRequests.keys)
        XCTAssertEqual(ids, Set([
            "ddiary.bp.d20260216.0900",
            "ddiary.bp.d20260216.2100",
            "ddiary.bp.d20260218.0900",
            "ddiary.bp.d20260218.2100"
        ]))
        XCTAssertEqual(center.pendingRequests.count, 4)

        let request = try XCTUnwrap(center.pendingRequests["ddiary.bp.d20260216.0900"])
        XCTAssertEqual(request.content.categoryIdentifier, UserNotificationsRepository.IDs.bpCategory)
        XCTAssertEqual(request.content.title, L10n.notificationBPTitle)
        let trigger = try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)
        XCTAssertFalse(trigger.repeats)
        XCTAssertEqual(trigger.dateComponents.year, 2026)
        XCTAssertEqual(trigger.dateComponents.month, 2)
        XCTAssertEqual(trigger.dateComponents.day, 16)
        XCTAssertEqual(trigger.dateComponents.hour, 9)
        XCTAssertEqual(trigger.dateComponents.minute, 0)
    }

    func test_scheduleBloodPressure_ignoresInvalidWeekdayValues() async throws {
        let center = FakeNotificationCenter()
        let calendar = Calendar.current
        let referenceNow = calendar.date(
            from: DateComponents(year: 2026, month: 2, day: 16, hour: 7, minute: 30)
        ) ?? Date()
        let repository = UserNotificationsRepository(
            center: center,
            calendar: calendar,
            now: { referenceNow },
            schedulingWindowDays: 2
        )

        try await repository.scheduleBloodPressure(times: [540], activeWeekdays: [0, 2, 8])

        XCTAssertEqual(Set(center.pendingRequests.keys), ["ddiary.bp.d20260216.0900"])
    }

    func test_scheduleBloodPressure_capsWindowToStayWithinPendingLimit() async throws {
        let center = FakeNotificationCenter()
        let calendar = Calendar.current
        let referenceNow = calendar.date(
            from: DateComponents(year: 2026, month: 2, day: 16, hour: 0, minute: 30)
        ) ?? Date()
        let repository = UserNotificationsRepository(
            center: center,
            calendar: calendar,
            now: { referenceNow },
            schedulingWindowDays: 28
        )

        try await repository.scheduleBloodPressure(
            times: [60, 180, 360, 540, 720, 900, 1080, 1260],
            activeWeekdays: Set(1...7)
        )

        XCTAssertEqual(center.pendingRequests.count, 64)
    }

    func test_scheduleGlucoseBeforeMeal_attachesQuickEntryMetadata() async throws {
        let center = FakeNotificationCenter()
        let calendar = Calendar.current
        let referenceNow = calendar.date(
            from: DateComponents(year: 2026, month: 2, day: 16, hour: 7, minute: 30)
        ) ?? Date()
        let repository = UserNotificationsRepository(
            center: center,
            calendar: calendar,
            now: { referenceNow },
            schedulingWindowDays: 1
        )

        try await repository.scheduleGlucoseBeforeMeal(
            breakfast: DateComponents(hour: 8, minute: 0),
            lunch: DateComponents(hour: 13, minute: 0),
            dinner: DateComponents(hour: 19, minute: 0),
            isEnabled: true
        )

        let request = try XCTUnwrap(
            center.pendingRequests.values.first {
                $0.content.title == L10n.notificationGlucoseBeforeLunchTitle
            }
        )
        XCTAssertEqual(
            request.content.userInfo[UserNotificationsRepository.PayloadKeys.mealSlot] as? String,
            MealSlot.lunch.rawValue
        )
        XCTAssertEqual(
            request.content.userInfo[UserNotificationsRepository.PayloadKeys.measurementType] as? String,
            GlucoseMeasurementType.beforeMeal.rawValue
        )
    }

    func test_rescheduleGlucose_removesExistingPrefixedRequestsAndSchedulesEnabledKindsOnly() async throws {
        let center = FakeNotificationCenter()
        let calendar = Calendar.current
        let referenceNow = calendar.date(
            from: DateComponents(year: 2026, month: 2, day: 16, hour: 7, minute: 30)
        ) ?? Date()
        let repository = UserNotificationsRepository(
            center: center,
            calendar: calendar,
            now: { referenceNow },
            schedulingWindowDays: 1
        )

        center.pendingRequests["ddiary.glucose.before.legacy"] = makeRequest(id: "ddiary.glucose.before.legacy")
        center.pendingRequests["ddiary.glucose.after.legacy"] = makeRequest(id: "ddiary.glucose.after.legacy")
        center.pendingRequests["ddiary.glucose.bedtime.legacy"] = makeRequest(id: "ddiary.glucose.bedtime.legacy")
        center.pendingRequests["ddiary.bp.legacy"] = makeRequest(id: "ddiary.bp.legacy")
        center.deliveredIdentifiers = [
            "ddiary.glucose.before.legacy",
            "ddiary.glucose.after.legacy",
            "ddiary.glucose.bedtime.legacy",
            "ddiary.bp.legacy"
        ]

        try await repository.rescheduleGlucose(
            breakfast: DateComponents(hour: 8, minute: 0),
            lunch: DateComponents(hour: 13, minute: 0),
            dinner: DateComponents(hour: 19, minute: 0),
            enableBeforeMeal: true,
            enableAfterMeal2h: false,
            enableBedtime: true,
            bedtimeTime: DateComponents(hour: 22, minute: 15)
        )

        XCTAssertNotNil(center.pendingRequests["ddiary.bp.legacy"])
        XCTAssertFalse(center.pendingRequests.keys.contains("ddiary.glucose.before.legacy"))
        XCTAssertFalse(center.pendingRequests.keys.contains("ddiary.glucose.after.legacy"))
        XCTAssertFalse(center.pendingRequests.keys.contains("ddiary.glucose.bedtime.legacy"))

        let beforeCount = center.pendingRequests.values.filter {
            $0.content.categoryIdentifier == UserNotificationsRepository.IDs.glucoseBeforeCategory
        }.count
        let afterCount = center.pendingRequests.values.filter {
            $0.content.categoryIdentifier == UserNotificationsRepository.IDs.glucoseAfterCategory
        }.count
        let bedtimeCount = center.pendingRequests.values.filter {
            $0.content.categoryIdentifier == UserNotificationsRepository.IDs.glucoseBedtimeCategory
        }.count
        XCTAssertEqual(beforeCount, 3)
        XCTAssertEqual(afterCount, 0)
        XCTAssertEqual(bedtimeCount, 1)

        let removedPending = Set(center.removedPendingIdentifiers.flatMap { $0 })
        XCTAssertTrue(removedPending.contains("ddiary.glucose.before.legacy"))
        XCTAssertTrue(removedPending.contains("ddiary.glucose.after.legacy"))
        XCTAssertTrue(removedPending.contains("ddiary.glucose.bedtime.legacy"))

        let removedDelivered = Set(center.removedDeliveredIdentifiers.flatMap { $0 })
        XCTAssertTrue(removedDelivered.contains("ddiary.glucose.before.legacy"))
        XCTAssertTrue(removedDelivered.contains("ddiary.glucose.after.legacy"))
        XCTAssertTrue(removedDelivered.contains("ddiary.glucose.bedtime.legacy"))
    }

    func test_rescheduleGlucose_capsWindowUsingRemainingPendingCapacity() async throws {
        let center = FakeNotificationCenter()
        let calendar = Calendar.current
        let referenceNow = calendar.date(
            from: DateComponents(year: 2026, month: 2, day: 16, hour: 7, minute: 30)
        ) ?? Date()
        let repository = UserNotificationsRepository(
            center: center,
            calendar: calendar,
            now: { referenceNow },
            schedulingWindowDays: 28
        )

        for index in 0..<56 {
            center.pendingRequests["ddiary.bp.preexisting.\(index)"] = makeRequest(id: "ddiary.bp.preexisting.\(index)")
        }

        try await repository.rescheduleGlucose(
            breakfast: DateComponents(hour: 8, minute: 0),
            lunch: DateComponents(hour: 13, minute: 0),
            dinner: DateComponents(hour: 19, minute: 0),
            enableBeforeMeal: true,
            enableAfterMeal2h: true,
            enableBedtime: true,
            bedtimeTime: DateComponents(hour: 22, minute: 15)
        )

        let glucoseIDs = Set(center.pendingRequests.keys.filter { $0.hasPrefix("ddiary.glucose.") })
        XCTAssertEqual(
            glucoseIDs,
            Set([
                "ddiary.glucose.before.d20260216.0800",
                "ddiary.glucose.before.d20260216.1300",
                "ddiary.glucose.before.d20260216.1900",
                "ddiary.glucose.after.d20260216.1000",
                "ddiary.glucose.after.d20260216.1500",
                "ddiary.glucose.after.d20260216.2100",
                "ddiary.glucose.bedtime.d20260216.2215"
            ])
        )
        XCTAssertEqual(center.pendingRequests.count, 63)
    }

    func test_cancelPlannedGlucoseNotification_cycleIdentifier_removesPendingAndDelivered() async {
        let center = FakeNotificationCenter()
        let repository = UserNotificationsRepository(center: center)
        let calendar = Calendar.current
        let scheduledDate = calendar.date(
            from: DateComponents(year: 2026, month: 2, day: 16, hour: 8, minute: 0)
        ) ?? Date()
        let cycleID = self.cycleID(
            prefix: UserNotificationsRepository.IDs.glucoseBeforePrefix,
            day: scheduledDate,
            hour: 8,
            minute: 0,
            calendar: calendar
        )
        center.pendingRequests[cycleID] = makeRequest(id: cycleID)
        center.deliveredIdentifiers = [cycleID]

        await repository.cancelPlannedGlucoseNotification(
            measurementType: .beforeMeal,
            at: scheduledDate
        )

        XCTAssertNil(center.pendingRequests[cycleID])
        XCTAssertTrue(Set(center.removedPendingIdentifiers.flatMap { $0 }).contains(cycleID))
        XCTAssertTrue(Set(center.removedDeliveredIdentifiers.flatMap { $0 }).contains(cycleID))
    }

    func test_cancelPlannedGlucoseNotification_repeatingIdentifier_removesPendingAndDelivered() async {
        let center = FakeNotificationCenter()
        let repository = UserNotificationsRepository(center: center)
        let calendar = Calendar.current
        let scheduledDate = calendar.date(
            from: DateComponents(year: 2026, month: 2, day: 16, hour: 13, minute: 0)
        ) ?? Date()
        let repeatingID = "ddiary.glucose.before.1300"
        center.pendingRequests[repeatingID] = makeRequest(id: repeatingID)
        center.deliveredIdentifiers = [repeatingID]

        await repository.cancelPlannedGlucoseNotification(
            measurementType: .beforeMeal,
            at: scheduledDate
        )

        XCTAssertNil(center.pendingRequests[repeatingID])
        XCTAssertTrue(Set(center.removedPendingIdentifiers.flatMap { $0 }).contains(repeatingID))
        XCTAssertTrue(Set(center.removedDeliveredIdentifiers.flatMap { $0 }).contains(repeatingID))
    }

    func test_cancelPlannedBloodPressureNotification_removesPendingAndDelivered() async {
        let center = FakeNotificationCenter()
        let repository = UserNotificationsRepository(center: center)
        let calendar = Calendar.current
        let scheduledDate = calendar.date(
            from: DateComponents(year: 2026, month: 2, day: 16, hour: 9, minute: 0)
        ) ?? Date()
        let dayID = "ddiary.bp.d20260216.0900"
        center.pendingRequests[dayID] = makeRequest(id: dayID)
        center.deliveredIdentifiers = [dayID]

        await repository.cancelPlannedBloodPressureNotification(at: scheduledDate)

        XCTAssertNil(center.pendingRequests[dayID])
        XCTAssertTrue(Set(center.removedPendingIdentifiers.flatMap { $0 }).contains(dayID))
        XCTAssertTrue(Set(center.removedDeliveredIdentifiers.flatMap { $0 }).contains(dayID))
    }

    func test_requestAuthorization_passthroughError() async {
        let center = FakeNotificationCenter()
        center.authorizationResult = .failure(TestError.forced)
        let repository = UserNotificationsRepository(center: center)

        do {
            _ = try await repository.requestAuthorization()
            XCTFail("Expected requestAuthorization to throw")
        } catch {
            // expected
        }
    }

    func test_rescheduleGlucoseCycle_schedulesOnlyCycleRemindersForWindow() async throws {
        let center = FakeNotificationCenter()
        let repository = UserNotificationsRepository(center: center)
        let calendar = Calendar.current
        let startDate = calendar.date(from: DateComponents(year: 2026, month: 2, day: 16, hour: 7, minute: 30)) ?? Date()

        let configuration = GlucoseCycleConfiguration(
            anchorDate: calendar.startOfDay(for: startDate),
            breakfast: DateComponents(hour: 8, minute: 0),
            lunch: DateComponents(hour: 13, minute: 0),
            dinner: DateComponents(hour: 19, minute: 0),
            bedtime: DateComponents(hour: 22, minute: 15)
        )

        try await repository.rescheduleGlucoseCycle(
            configuration: configuration,
            startDate: startDate,
            numberOfDays: 4
        )

        let day1 = calendar.startOfDay(for: startDate)
        let day2 = calendar.date(byAdding: .day, value: 1, to: day1) ?? day1
        let day3 = calendar.date(byAdding: .day, value: 2, to: day1) ?? day1
        let day4 = calendar.date(byAdding: .day, value: 3, to: day1) ?? day1

        let expected = Set([
            cycleID(prefix: UserNotificationsRepository.IDs.glucoseBeforePrefix, day: day1, hour: 8, minute: 0, calendar: calendar),
            cycleID(prefix: UserNotificationsRepository.IDs.glucoseAfterPrefix, day: day1, hour: 10, minute: 0, calendar: calendar),
            cycleID(prefix: UserNotificationsRepository.IDs.glucoseBeforePrefix, day: day2, hour: 13, minute: 0, calendar: calendar),
            cycleID(prefix: UserNotificationsRepository.IDs.glucoseAfterPrefix, day: day2, hour: 15, minute: 0, calendar: calendar),
            cycleID(prefix: UserNotificationsRepository.IDs.glucoseBeforePrefix, day: day3, hour: 19, minute: 0, calendar: calendar),
            cycleID(prefix: UserNotificationsRepository.IDs.glucoseAfterPrefix, day: day3, hour: 21, minute: 0, calendar: calendar),
            cycleID(prefix: UserNotificationsRepository.IDs.glucoseBedtimePrefix, day: day4, hour: 22, minute: 15, calendar: calendar),
        ])

        XCTAssertEqual(Set(center.pendingRequests.keys), expected)
    }

    func test_scheduleOneOff_attachesProvidedUserInfo() async {
        let center = FakeNotificationCenter()
        let repository = UserNotificationsRepository(center: center)
        let fireDate = Calendar.current.date(
            from: DateComponents(year: 2026, month: 2, day: 17, hour: 15, minute: 30, second: 42)
        ) ?? Date()

        await repository.scheduleOneOff(
            at: fireDate,
            identifier: "ddiary.oneoff.test",
            title: "title",
            body: "body",
            categoryIdentifier: UserNotificationsRepository.IDs.glucoseBeforeCategory,
            userInfo: [
                UserNotificationsRepository.PayloadKeys.mealSlot: MealSlot.breakfast.rawValue,
                UserNotificationsRepository.PayloadKeys.measurementType: GlucoseMeasurementType.beforeMeal.rawValue,
            ]
        )

        guard let request = center.pendingRequests["ddiary.oneoff.test"] else {
            XCTFail("Expected one-off request to be scheduled")
            return
        }
        XCTAssertEqual(
            request.content.userInfo[UserNotificationsRepository.PayloadKeys.mealSlot] as? String,
            MealSlot.breakfast.rawValue
        )
        XCTAssertEqual(
            request.content.userInfo[UserNotificationsRepository.PayloadKeys.measurementType] as? String,
            GlucoseMeasurementType.beforeMeal.rawValue
        )
        let trigger = request.trigger as? UNCalendarNotificationTrigger
        XCTAssertEqual(trigger?.dateComponents.second, 42)
    }

    func test_scheduleOneOff_whenPendingCapacityIsFull_evictsFarthestAndSchedulesNewRequest() async {
        let center = FakeNotificationCenter()
        center.maxPendingRequests = 64
        let calendar = Calendar.current
        let baseDate = calendar.date(
            from: DateComponents(year: 2099, month: 2, day: 17, hour: 8, minute: 0)
        ) ?? Date()

        for index in 0..<64 {
            let id = "ddiary.prefill.\(index)"
            let date = calendar.date(byAdding: .minute, value: index, to: baseDate) ?? baseDate
            center.pendingRequests[id] = makeRequest(
                id: id,
                date: date,
                categoryIdentifier: UserNotificationsRepository.IDs.bpCategory,
                title: L10n.notificationBPTitle
            )
        }

        let repository = UserNotificationsRepository(center: center)
        let oneOffDate = calendar.date(byAdding: .minute, value: 15, to: baseDate) ?? baseDate
        await repository.scheduleOneOff(
            at: oneOffDate,
            identifier: "ddiary.oneoff.capacity-test",
            title: "title",
            body: "body",
            categoryIdentifier: UserNotificationsRepository.IDs.glucoseBeforeCategory,
            userInfo: [:]
        )

        XCTAssertEqual(center.pendingRequests.count, 64)
        XCTAssertNotNil(center.pendingRequests["ddiary.oneoff.capacity-test"])
        let removedPrefillCount = (0..<64).filter { center.pendingRequests["ddiary.prefill.\($0)"] == nil }.count
        XCTAssertEqual(removedPrefillCount, 1)
    }

    func test_rescheduleShiftedAfterMeal2hNotification_cancelsOriginalAndSchedulesShiftedOneOff() async {
        let center = FakeNotificationCenter()
        let repository = UserNotificationsRepository(center: center)
        let calendar = Calendar.current
        let originalAfterDate = calendar.date(
            from: DateComponents(year: 2099, month: 2, day: 16, hour: 15, minute: 0)
        ) ?? Date()
        let shiftedAfterDate = calendar.date(
            from: DateComponents(year: 2099, month: 2, day: 16, hour: 15, minute: 35)
        ) ?? Date()

        let originalCycleID = cycleID(
            prefix: UserNotificationsRepository.IDs.glucoseAfterPrefix,
            day: originalAfterDate,
            hour: 15,
            minute: 0,
            calendar: calendar
        )
        let repeatingID = "ddiary.glucose.after.1500"
        center.pendingRequests[originalCycleID] = makeRequest(id: originalCycleID)
        center.pendingRequests[repeatingID] = makeRequest(id: repeatingID)
        center.deliveredIdentifiers = [originalCycleID, repeatingID]

        await repository.rescheduleShiftedAfterMeal2hNotification(
            mealSlot: .lunch,
            originalAfterDate: originalAfterDate,
            shiftedAfterDate: shiftedAfterDate
        )

        XCTAssertNil(center.pendingRequests[originalCycleID])
        let shiftedID = shiftedAfterID(mealSlot: .lunch, day: shiftedAfterDate, calendar: calendar)
        let shiftedRequest = try? XCTUnwrap(center.pendingRequests[shiftedID])
        XCTAssertNotNil(shiftedRequest)
        XCTAssertEqual(shiftedRequest?.content.categoryIdentifier, UserNotificationsRepository.IDs.glucoseAfterCategory)
        XCTAssertEqual(shiftedRequest?.content.title, L10n.notificationGlucoseAfterLunch2hTitle)
        XCTAssertEqual(
            shiftedRequest?.content.userInfo[UserNotificationsRepository.PayloadKeys.mealSlot] as? String,
            MealSlot.lunch.rawValue
        )
        XCTAssertEqual(
            shiftedRequest?.content.userInfo[UserNotificationsRepository.PayloadKeys.measurementType] as? String,
            GlucoseMeasurementType.afterMeal2h.rawValue
        )
        let removedPending = Set(center.removedPendingIdentifiers.flatMap { $0 })
        XCTAssertTrue(removedPending.contains(originalCycleID))
        XCTAssertTrue(removedPending.contains(repeatingID))
        let removedDelivered = Set(center.removedDeliveredIdentifiers.flatMap { $0 })
        XCTAssertTrue(removedDelivered.contains(originalCycleID))
        XCTAssertTrue(removedDelivered.contains(repeatingID))
    }

    func test_scheduleDebugNotifications_useProductionCategoriesAndPayload() async {
        let center = FakeNotificationCenter()
        let repository = UserNotificationsRepository(center: center)

        await repository.scheduleDebugBloodPressureNotification(after: 10)
        await repository.scheduleDebugGlucoseNotification(after: 10)

        let bpRequest = center.pendingRequests.values.first {
            $0.identifier.hasPrefix("ddiary.debug.bp.")
        }
        XCTAssertNotNil(bpRequest)
        XCTAssertEqual(bpRequest?.content.categoryIdentifier, UserNotificationsRepository.IDs.bpCategory)
        XCTAssertEqual(bpRequest?.content.title, L10n.notificationBPTitle)

        let glucoseRequest = center.pendingRequests.values.first {
            $0.identifier.hasPrefix("ddiary.debug.glucose.before.breakfast.")
        }
        XCTAssertNotNil(glucoseRequest)
        XCTAssertEqual(glucoseRequest?.content.categoryIdentifier, UserNotificationsRepository.IDs.glucoseBeforeCategory)
        XCTAssertEqual(glucoseRequest?.content.title, L10n.notificationGlucoseBeforeBreakfastTitle)
        XCTAssertEqual(
            glucoseRequest?.content.userInfo[UserNotificationsRepository.PayloadKeys.mealSlot] as? String,
            MealSlot.breakfast.rawValue
        )
        XCTAssertEqual(
            glucoseRequest?.content.userInfo[UserNotificationsRepository.PayloadKeys.measurementType] as? String,
            GlucoseMeasurementType.beforeMeal.rawValue
        )
    }

    func test_scheduledReminders_returnsPendingAndDeliveredForCurrentDay() async {
        let center = FakeNotificationCenter()
        let repository = UserNotificationsRepository(center: center)
        let calendar = Calendar.current
        let pendingDate = Date().addingTimeInterval(120)
        let today = pendingDate
        let deliveredDate = pendingDate

        center.pendingRequests["bp.pending"] = makeRequest(
            id: "bp.pending",
            date: pendingDate,
            categoryIdentifier: UserNotificationsRepository.IDs.bpCategory,
            title: L10n.notificationBPTitle
        )
        center.deliveredRecordsByID["gl.delivered"] = DeliveredNotificationRecord(
            identifier: "gl.delivered",
            deliveredDate: deliveredDate,
            categoryIdentifier: UserNotificationsRepository.IDs.glucoseBeforeCategory,
            title: L10n.notificationGlucoseBeforeLunchTitle,
            mealSlotRawValue: MealSlot.lunch.rawValue,
            measurementTypeRawValue: GlucoseMeasurementType.beforeMeal.rawValue
        )
        center.deliveredIdentifiers.insert("gl.delivered")

        let reminders = await repository.scheduledReminders(on: today)

        XCTAssertEqual(reminders.count, 2)
        XCTAssertTrue(reminders.contains(where: { reminder in
            guard case .bloodPressure = reminder.kind else { return false }
            return calendar.isDate(reminder.date, equalTo: pendingDate, toGranularity: .minute)
        }))
        XCTAssertTrue(reminders.contains(where: { reminder in
            guard case .glucose(let mealSlot, let measurementType) = reminder.kind else { return false }
            return mealSlot == .lunch
                && measurementType == .beforeMeal
                && calendar.isDate(reminder.date, equalTo: deliveredDate, toGranularity: .minute)
        }))
    }

    func test_scheduledReminders_ignoresEntriesOutsideRequestedDay() async {
        let center = FakeNotificationCenter()
        let repository = UserNotificationsRepository(center: center)
        let calendar = Calendar.current
        let today = Date()
        let tomorrow = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: today)
        ) ?? today.addingTimeInterval(24 * 60 * 60)

        center.pendingRequests["bp.tomorrow"] = makeRequest(
            id: "bp.tomorrow",
            date: tomorrow,
            categoryIdentifier: UserNotificationsRepository.IDs.bpCategory,
            title: L10n.notificationBPTitle
        )
        center.deliveredRecordsByID["gl.tomorrow"] = DeliveredNotificationRecord(
            identifier: "gl.tomorrow",
            deliveredDate: tomorrow,
            categoryIdentifier: UserNotificationsRepository.IDs.glucoseBedtimeCategory,
            title: L10n.notificationGlucoseBedtimeTitle,
            mealSlotRawValue: MealSlot.none.rawValue,
            measurementTypeRawValue: GlucoseMeasurementType.bedtime.rawValue
        )
        center.deliveredIdentifiers.insert("gl.tomorrow")

        let reminders = await repository.scheduledReminders(on: today)

        XCTAssertTrue(reminders.isEmpty)
    }

    private func makeRequest(id: String) -> UNNotificationRequest {
        UNNotificationRequest(
            identifier: id,
            content: UNMutableNotificationContent(),
            trigger: nil
        )
    }

    private func makeRequest(
        id: String,
        date: Date,
        categoryIdentifier: String,
        title: String,
        mealSlot: MealSlot? = nil,
        measurementType: GlucoseMeasurementType? = nil
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.categoryIdentifier = categoryIdentifier
        content.title = title
        var userInfo: [AnyHashable: Any] = [:]
        if let mealSlot {
            userInfo[UserNotificationsRepository.PayloadKeys.mealSlot] = mealSlot.rawValue
        }
        if let measurementType {
            userInfo[UserNotificationsRepository.PayloadKeys.measurementType] = measurementType.rawValue
        }
        if !userInfo.isEmpty {
            content.userInfo = userInfo
        }
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    }

    private func cycleID(prefix: String, day: Date, hour: Int, minute: Int, calendar: Calendar) -> String {
        var dayParts = calendar.dateComponents([.year, .month, .day], from: day)
        dayParts.hour = hour
        dayParts.minute = minute
        let y = dayParts.year ?? 0
        let mo = dayParts.month ?? 0
        let d = dayParts.day ?? 0
        return "\(prefix)d\(String(format: "%04d", y))\(String(format: "%02d", mo))\(String(format: "%02d", d)).\(String(format: "%02d", hour))\(String(format: "%02d", minute))"
    }

    private func shiftedAfterID(mealSlot: MealSlot, day: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: day)
        let y = parts.year ?? 0
        let mo = parts.month ?? 0
        let d = parts.day ?? 0
        let h = parts.hour ?? 0
        let m = parts.minute ?? 0
        return "\(UserNotificationsRepository.IDs.glucoseAfterPrefix)shifted.\(mealSlot.rawValue).d\(String(format: "%04d", y))\(String(format: "%02d", mo))\(String(format: "%02d", d)).\(String(format: "%02d", h))\(String(format: "%02d", m))"
    }
}

private final class FakeNotificationCenter: UserNotificationCentering, @unchecked Sendable {
    var authorizationResult: Result<Bool, Error> = .success(true)
    var categories: [UNNotificationCategory] = []
    var pendingRequests: [String: UNNotificationRequest] = [:]
    var maxPendingRequests: Int?
    var forcedAddFailures = 0
    var deliveredIdentifiers: Set<String> = [] {
        didSet {
            deliveredRecordsByID = deliveredRecordsByID.filter { deliveredIdentifiers.contains($0.key) }
            for identifier in deliveredIdentifiers where deliveredRecordsByID[identifier] == nil {
                deliveredRecordsByID[identifier] = DeliveredNotificationRecord(
                    identifier: identifier,
                    deliveredDate: Date(),
                    categoryIdentifier: "",
                    title: "",
                    mealSlotRawValue: nil,
                    measurementTypeRawValue: nil
                )
            }
        }
    }
    var deliveredRecordsByID: [String: DeliveredNotificationRecord] = [:]
    var removedPendingIdentifiers: [[String]] = []
    var removedDeliveredIdentifiers: [[String]] = []

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        switch authorizationResult {
        case .success(let granted):
            return granted
        case .failure(let error):
            throw error
        }
    }

    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {
        self.categories = Array(categories)
    }

    func addOrReplace(request: UNNotificationRequest) async -> Bool {
        if forcedAddFailures > 0 {
            forcedAddFailures -= 1
            return false
        }
        if let maxPendingRequests, pendingRequests[request.identifier] == nil, pendingRequests.count >= maxPendingRequests {
            return false
        }
        pendingRequests[request.identifier] = request
        return true
    }

    func removePendingNotificationRequests(withIdentifiers ids: [String]) {
        removedPendingIdentifiers.append(ids)
        for id in ids {
            pendingRequests.removeValue(forKey: id)
        }
    }

    func removeDeliveredNotifications(withIdentifiers ids: [String]) {
        removedDeliveredIdentifiers.append(ids)
        for id in ids {
            deliveredIdentifiers.remove(id)
            deliveredRecordsByID.removeValue(forKey: id)
        }
    }

    func removeAllPendingNotificationRequests() {
        pendingRequests.removeAll()
    }

    func removeAllDeliveredNotifications() {
        deliveredIdentifiers.removeAll()
        deliveredRecordsByID.removeAll()
    }

    func pendingRequestIdentifiers() async -> [String] {
        pendingRequests.keys.sorted()
    }

    func deliveredNotificationIdentifiers() async -> [String] {
        deliveredIdentifiers.sorted()
    }

    func pendingNotificationRecords() async -> [PendingNotificationRecord] {
        pendingRequests.values.map { request in
            PendingNotificationRecord(
                identifier: request.identifier,
                nextTriggerDate: {
                    guard let calendarTrigger = request.trigger as? UNCalendarNotificationTrigger else { return nil }
                    return calendarTrigger.nextTriggerDate()
                }(),
                categoryIdentifier: request.content.categoryIdentifier,
                title: request.content.title,
                mealSlotRawValue: request.content.userInfo[UserNotificationsRepository.PayloadKeys.mealSlot] as? String,
                measurementTypeRawValue: request.content.userInfo[UserNotificationsRepository.PayloadKeys.measurementType] as? String
            )
        }
    }

    func deliveredNotificationRecords() async -> [DeliveredNotificationRecord] {
        Array(deliveredRecordsByID.values)
    }
}
