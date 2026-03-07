import Foundation

enum L10n {
    // MARK: - Tabs / Titles
    static let tabToday = tr("tab.today", "Today")
    static let tabHistory = tr("tab.history", "History")
    static let tabSettings = tr("tab.settings", "Settings")
    static let tabDebug = tr("tab.debug", "Debug")

    static let screenTodayTitle = tr("screen.today.title", "Today")
    static let screenHistoryTitle = tr("screen.history.title", "History")
    static let screenSettingsTitle = tr("screen.settings.title", "Settings")
    static let screenDebugTitle = tr("screen.debug.title", "Debug")

    // MARK: - Debug
    static let debugNotificationsHint = tr("debug.notifications.hint", "Schedules in 10 seconds.")
    static let debugGenerateBPNotification = tr(
        "debug.notifications.generate_bp",
        "Generate test notification for BP"
    )
    static let debugGenerateGlucoseNotification = tr(
        "debug.notifications.generate_glucose",
        "Generate test notification for Glucose"
    )
    static let debugScheduledBP = tr(
        "debug.notifications.scheduled_bp",
        "Scheduled BP test notification."
    )
    static let debugScheduledGlucose = tr(
        "debug.notifications.scheduled_glucose",
        "Scheduled Glucose test notification."
    )
    static let debugAuthorizationDenied = tr(
        "debug.notifications.authorization_denied",
        "Notifications permission is not granted."
    )
    static func debugScheduleFailed(_ message: String) -> String {
        String(
            format: tr(
                "debug.notifications.schedule_failed_format",
                "Failed to schedule test notification: %@"
            ),
            message
        )
    }

    // MARK: - Today
    static let todayLoading = tr("today.loading", "Loading…")
    static let todayBlockNow = tr("today.block.now", "Now")
    static let todayBlockLater = tr("today.block.later", "Later Today")
    static let todayBlockOverdue = tr("today.block.overdue", "Overdue")
    static let todayBlockCompleted = tr("today.block.completed", "Completed")
    static let todayQuickEntryTitle = tr("today.quick_entry.title", "Quick Entry")
    static let todayCycleSwitchAccessibilityLabel = tr(
        "today.cycle_switch.accessibility.label",
        "Switch daily cycle target"
    )
    static let todayCycleSwitchAccessibilityHint = tr(
        "today.cycle_switch.accessibility.hint",
        "Opens a menu to change the daily cycle target"
    )
    static let slotStatusScheduled = tr("slot.status.scheduled", "Scheduled")
    static let slotStatusDue = tr("slot.status.due", "Due")
    static let slotStatusMissed = tr("slot.status.missed", "Missed")
    static let slotStatusCompleted = tr("slot.status.completed", "Done")

    // MARK: - History
    static let historyLoading = tr("history.loading", "Loading…")
    static let historyQuickEntryTitle = tr("history.quick_entry.title", "Quick Entry")
    static let historyEmptyTitle = tr("history.empty.title", "No measurements")
    static let historyEmptyDescription = tr(
        "history.empty.description",
        "There are no entries for the selected filter and date range."
    )
    static let cloudRestoreTitle = tr("cloud_restore.title", "Restoring from iCloud…")
    static let cloudRestoreHistoryDescription = tr(
        "cloud_restore.history.description",
        "If you previously used DDiary, your history may appear shortly after reinstall."
    )
    static let cloudRestoreRefreshNow = tr("cloud_restore.action.refresh_now", "Refresh now")
    static let historyFilterLabel = tr("history.filter.label", "Filter")
    static let historyFilterBoth = tr("history.filter.both", "Both")
    static let historyFilterBP = tr("history.filter.bp", "BP")
    static let historyFilterGlucose = tr("history.filter.glucose", "Glucose")
    static let historyRangeToday = tr("history.range.today", "Today")
    static let historyRange7Days = tr("history.range.7_days", "7 days")
    static let historyRange30Days = tr("history.range.30_days", "30 days")
    static func historyRangeAccessibilityLabel(_ title: String) -> String {
        String(
            format: tr("history.range.accessibility_label_format", "Range %@"),
            title
        )
    }

    // MARK: - Quick Entry
    static let quickEntryActionCancel = tr("quick_entry.action.cancel", "Cancel")
    static let quickEntryActionSave = tr("quick_entry.action.save", "Save")
    static let quickEntryActionDone = tr("quick_entry.action.done", "Done")
    static let quickEntryAlertErrorTitle = tr("quick_entry.alert.error.title", "Error")
    static let quickEntryAlertOK = tr("quick_entry.alert.ok", "OK")
    static let quickEntryAlertUnusualValuesTitle = tr("quick_entry.alert.unusual_values.title", "Unusual values")
    static let quickEntryAlertSaveAnyway = tr("quick_entry.alert.save_anyway", "Save anyway")
    static let quickEntryErrorSaveFailed = tr("quick_entry.error.save_failed", "Failed to save. Please try again.")
    static let quickEntryBadgeUnusual = tr("quick_entry.badge.unusual", "Unusual")

    static let quickEntryBpFieldSystolic = tr("quick_entry.bp.field.systolic", "Systolic")
    static let quickEntryBpFieldDiastolic = tr("quick_entry.bp.field.diastolic", "Diastolic")
    static let quickEntryBpFieldPulse = tr("quick_entry.bp.field.pulse", "Pulse")

    static let quickEntryGlucoseTitle = tr("quick_entry.glucose.title", "Glucose")
    static let quickEntryGlucoseValuePlaceholder = tr("quick_entry.glucose.value_placeholder", "Value")
    static let unitMmolL = tr("unit.mmol_l", "mmol/L")
    static let unitMgDL = tr("unit.mg_dl", "mg/dL")
    static let measurementCommentPlaceholder = tr("measurement.comment.placeholder", "Comment")
    static let measurementAddComment = tr("measurement.add_comment", "Add comment")

    static let historyRowNotEntered = tr("history.row.not_entered", "Not entered")
    static let historyRowCheckValue = tr("history.row.check_value", "Check value")
    static func historyRowPulse(_ value: String) -> String {
        String(
            format: tr("history.row.pulse_format", "Pulse %@"),
            value
        )
    }

    // MARK: - Summary
    static let summaryTitle = tr("summary.title", "Summary")
    static let summaryCount = tr("summary.count", "Count")
    static let summarySysMinMaxAvg = tr("summary.sys_min_max_avg", "SYS min/max/avg")
    static let summaryDiaMinMaxAvg = tr("summary.dia_min_max_avg", "DIA min/max/avg")
    static let summaryPulseMinMaxAvg = tr("summary.pulse_min_max_avg", "Pulse min/max/avg")
    static let summaryMinMaxAvg = tr("summary.min_max_avg", "Min/Max/Avg")

    static func quickEntryExpectedRange(min: String, max: String) -> String {
        String(
            format: tr("quick_entry.validation.expected_range_format", "Expected %@–%@"),
            min,
            max
        )
    }

    static func quickEntryExpectedRange(min: Int, max: Int) -> String {
        quickEntryExpectedRange(min: String(min), max: String(max))
    }

    static func quickEntryFieldExpected(_ field: String, min: Int, max: Int) -> String {
        String(
            format: tr("quick_entry.validation.field_expected_format", "%@: %@"),
            field,
            quickEntryExpectedRange(min: min, max: max)
        )
    }

    static func quickEntryMinMax(min: String, max: String) -> String {
        String(
            format: tr("quick_entry.validation.min_max_format", "Min %@ / Max %@"),
            min,
            max
        )
    }

    static func quickEntryGlucoseWarning(_ range: String) -> String {
        String(
            format: tr("quick_entry.validation.glucose_warning_format", "Glucose: %@"),
            range
        )
    }

    // MARK: - Settings (Sections/Rows)
    static let settingsTitle = tr("settings.title", "Settings")
    static let settingsShareExportedCSV = tr("settings.share.exported_csv", "Exported CSV")
    static let settingsShareNoFile = tr("settings.share.no_file", "No file")

    static let settingsSectionUnits = tr("settings.section.units", "Units")
    static let settingsSectionMealTimes = tr("settings.section.meal_times", "Meal Times")
    static let settingsSectionBPReminders = tr("settings.section.bp_reminders", "Blood Pressure Reminders")
    static let settingsSectionGlucoseReminders = tr("settings.section.glucose_reminders", "Glucose Reminders")
    static let settingsSectionThresholds = tr("settings.section.thresholds", "Thresholds")
    static let settingsSectionGoogleBackup = tr("settings.section.google_backup", "Google Sheets Backup")
    static let settingsSectionExport = tr("settings.section.export", "Export")
    static let settingsSectionFeedbackAbout = tr("settings.section.feedback_about", "Feedback & About")

    static let settingsRowGlucoseUnit = tr("settings.row.glucose_unit", "Glucose Unit")
    static let settingsRowBreakfast = tr("settings.row.breakfast", "Breakfast")
    static let settingsRowLunch = tr("settings.row.lunch", "Lunch")
    static let settingsRowDinner = tr("settings.row.dinner", "Dinner")
    static let settingsRowBedtime = tr("settings.row.bedtime", "Bedtime")
    static let settingsRowBedtimeSlotEnabled = tr("settings.row.bedtime_slot_enabled", "Bedtime slot enabled")
    static let settingsRowNoTimesConfigured = tr("settings.row.no_times_configured", "No times configured")
    static let settingsRowAddTime = tr("settings.row.add_time", "Add time")
    static let settingsRowActiveWeekdays = tr("settings.row.active_weekdays", "Active weekdays")
    static let settingsRowBeforeMeal = tr("settings.row.before_meal", "Before meal")
    static let settingsRowAfterMeal2h = tr("settings.row.after_meal_2h", "After meal (2h)")
    static let settingsRowBedtimeToggle = tr("settings.row.bedtime_toggle", "Bedtime")
    static let settingsRowDailyCycleMode = tr("settings.row.daily_cycle_mode", "Daily cycle mode (1 per day)")
    static let settingsRowDailyCycleTodayIs = tr("settings.row.daily_cycle_today_is", "Today is")
    static func settingsRowDailyCycleSwitchTo(_ value: String) -> String {
        String(
            format: tr("settings.row.daily_cycle_switch_to_format", "Switch to %@"),
            value
        )
    }
    static let settingsRowBloodPressure = tr("settings.row.blood_pressure", "Blood Pressure")
    static let settingsRowGlucose = tr("settings.row.glucose", "Glucose")
    static let settingsRowSysMin = tr("settings.row.sys_min", "SYS min")
    static let settingsRowSysMax = tr("settings.row.sys_max", "SYS max")
    static let settingsRowDiaMin = tr("settings.row.dia_min", "DIA min")
    static let settingsRowDiaMax = tr("settings.row.dia_max", "DIA max")
    static let settingsRowGlucoseMin = tr("settings.row.glucose_min", "Glucose min")
    static let settingsRowGlucoseMax = tr("settings.row.glucose_max", "Glucose max")
    static let settingsRowConnect = tr("settings.row.connect", "Connect")
    static let settingsRowSyncNow = tr("settings.row.sync_now", "Sync Now")
    static let settingsRowDisconnect = tr("settings.row.disconnect", "Disconnect")
    static let settingsRowFrom = tr("settings.row.from", "From")
    static let settingsRowTo = tr("settings.row.to", "To")
    static let settingsRowIncludeBP = tr("settings.row.include_bp", "Include BP")
    static let settingsRowIncludeGlucose = tr("settings.row.include_glucose", "Include Glucose")
    static let settingsRowExportCSV = tr("settings.row.export_csv", "Export CSV")
    static let settingsRowSendFeedback = tr("settings.row.send_feedback", "Send Feedback")
    static let settingsRowSave = tr("settings.row.save", "Save")
    static let settingsDisclaimerMedical = tr("settings.disclaimer.medical", "DDiary is not a medical device. Consult your physician for medical advice.")
    static let settingsFeedbackEmailSubject = tr("settings.feedback.email_subject", "DDiary Feedback")
    static let mealSnack = tr("meal.snack", "Snack")
    static let glucoseTypeFasting = tr("glucose.type.fasting", "Fasting")
    static let glucoseTypeRandom = tr("glucose.type.random", "Random")
    static let measurementTypeFingerstick = tr("measurement.type.fingerstick", "Fingerstick")
    static let measurementTypeSensor = tr("measurement.type.sensor", "Sensor")
    static let measurementTypeCapillary = tr("measurement.type.capillary", "Capillary")
    static let measurementTypeVenous = tr("measurement.type.venous", "Venous")

    // MARK: - Notifications
    static let notificationActionEnter = tr("notification.action.enter", "Enter")
    static let notificationActionSkip = tr("notification.action.skip", "Skip")
    static func notificationActionSnooze(_ minutes: Int) -> String {
        String(
            format: tr("notification.action.snooze_format", "Snooze %dm"),
            minutes
        )
    }

    static let notificationBPTitle = tr("notification.bp.title", "Blood Pressure")
    static let notificationBPBody = tr("notification.bp.body", "Time to measure your blood pressure.")

    static let notificationGlucoseBeforeBreakfastTitle = tr("notification.glucose.before_breakfast.title", "Glucose - Before Breakfast")
    static let notificationGlucoseBeforeBreakfastBody = tr("notification.glucose.before_breakfast.body", "Log glucose before breakfast.")
    static let notificationGlucoseBeforeLunchTitle = tr("notification.glucose.before_lunch.title", "Glucose - Before Lunch")
    static let notificationGlucoseBeforeLunchBody = tr("notification.glucose.before_lunch.body", "Log glucose before lunch.")
    static let notificationGlucoseBeforeDinnerTitle = tr("notification.glucose.before_dinner.title", "Glucose - Before Dinner")
    static let notificationGlucoseBeforeDinnerBody = tr("notification.glucose.before_dinner.body", "Log glucose before dinner.")

    static let notificationGlucoseAfterBreakfast2hTitle = tr("notification.glucose.after_breakfast_2h.title", "Glucose - After Breakfast (2h)")
    static let notificationGlucoseAfterBreakfast2hBody = tr("notification.glucose.after_breakfast_2h.body", "Log glucose 2 hours after breakfast.")
    static let notificationGlucoseAfterLunch2hTitle = tr("notification.glucose.after_lunch_2h.title", "Glucose - After Lunch (2h)")
    static let notificationGlucoseAfterLunch2hBody = tr("notification.glucose.after_lunch_2h.body", "Log glucose 2 hours after lunch.")
    static let notificationGlucoseAfterDinner2hTitle = tr("notification.glucose.after_dinner_2h.title", "Glucose - After Dinner (2h)")
    static let notificationGlucoseAfterDinner2hBody = tr("notification.glucose.after_dinner_2h.body", "Log glucose 2 hours after dinner.")

    static let notificationGlucoseBedtimeTitle = tr("notification.glucose.bedtime.title", "Glucose - Bedtime")
    static let notificationGlucoseBedtimeBody = tr("notification.glucose.bedtime.body", "Log bedtime glucose.")
    static let notificationRescheduledFromBreakfast = tr("notification.glucose.rescheduled_from_breakfast", "Rescheduled from breakfast.")

    // MARK: - Export
    static let exportSectionBP = tr("export.section.bp", "BP")
    static let exportSectionGlucose = tr("export.section.glucose", "Glucose")
    static let exportHeaderTimestamp = tr("export.header.timestamp", "timestamp")
    static let exportHeaderDate = tr("export.header.date", "date")
    static let exportHeaderTime = tr("export.header.time", "time")
    static let exportHeaderSystolic = tr("export.header.systolic", "systolic")
    static let exportHeaderDiastolic = tr("export.header.diastolic", "diastolic")
    static let exportHeaderPulse = tr("export.header.pulse", "pulse")
    static let exportHeaderComment = tr("export.header.comment", "comment")
    static let exportHeaderId = tr("export.header.id", "id")
    static let exportHeaderValue = tr("export.header.value", "value")
    static let exportHeaderUnit = tr("export.header.unit", "unit")
    static let exportHeaderMeasurementType = tr("export.header.measurement_type", "measurementType")
    static let exportHeaderMealSlot = tr("export.header.meal_slot", "mealSlot")

    // MARK: - Settings dynamic text
    static func settingsPendingFailed(pending: Int, failed: Int) -> String {
        String(
            format: tr("settings.row.pending_failed_format", "Pending: %d  Failed: %d"),
            pending,
            failed
        )
    }

    static func settingsLastSync(_ value: String) -> String {
        String(
            format: tr("settings.row.last_sync_format", "Last sync: %@"),
            value
        )
    }

    static let settingsLastSyncNone = tr("settings.row.last_sync_none", "Last sync: —")
    static let cloudRestoreSettingsDescription = tr(
        "cloud_restore.settings.description",
        "If you used DDiary before, Google backup details may appear after iCloud restore completes."
    )

    // MARK: - SettingsViewModel messages
    static let settingsErrorSavedButRemindersNotUpdated = tr(
        "settings.error.saved_but_reminders_not_updated",
        "Settings saved, but reminders could not be updated."
    )

    static let settingsGoogleSummaryNotConnected = tr("settings.google.summary.not_connected", "Not connected")
    static let settingsGoogleSummaryConnected = tr("settings.google.summary.connected", "Connected")
    static func settingsGoogleSummaryConnected(uid: String) -> String {
        String(
            format: tr("settings.google.summary.connected_with_uid_format", "Connected (%@)"),
            uid
        )
    }
    static let settingsGoogleSummaryAwaitingCredentials = tr(
        "settings.google.summary.awaiting_credentials",
        "Enabled, awaiting credentials"
    )
    static let settingsGoogleStartingSignIn = tr("settings.google.summary.starting_signin", "Starting Google sign-in…")
    static let settingsGoogleSummarySyncing = tr("settings.google.summary.syncing", "Syncing with Google…")
    static func settingsGoogleSpreadsheetCreationFailed(_ message: String) -> String {
        String(
            format: tr("settings.google.error.spreadsheet_creation_failed_format", "Failed to create spreadsheet: %@"),
            message
        )
    }
    static let settingsGoogleSpreadsheetTitle = tr("settings.google.spreadsheet_title", "DIA-ry backup")
    static let settingsGoogleSpreadsheetKnownTitles: [String] = [
        "DIA-ry backup",
        "Резервная копия DIA-ry",
        "DDiary Backup",
        "Резервная копия DDiary"
    ]

    // MARK: - Startup
    static let cloudSyncUnavailableTitle = tr("app.cloud_fallback.title", "iCloud sync unavailable")
    static let cloudSyncUnavailableMessage = tr(
        "app.cloud_fallback.message",
        "DDiary is using local storage on this device for now. Changes won't sync with iCloud until a later launch can reconnect."
    )
    static let startupTitle = tr("app.startup.title", "Unable to start DDiary")
    static let startupRecoveryHint = tr(
        "app.startup.recovery_hint",
        "Please restart the app. If the problem persists, reinstall the app or contact support."
    )
    static func startupStorageInitFailed(_ message: String) -> String {
        String(
            format: tr(
                "app.startup.error.storage_init_failed_format",
                "Failed to initialize local data storage. %@"
            ),
            message
        )
    }

    // MARK: - Helpers
    private static func tr(_ key: String, _ defaultValue: String) -> String {
        Bundle.main.localizedString(forKey: key, value: defaultValue, table: "Localizable")
    }
}
