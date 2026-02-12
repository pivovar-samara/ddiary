# DDiary Manual QA Checklist (Pre-release)

Use this checklist for final iPhone/iPad smoke validation before tagging an RC.

## Test Run Metadata

- [ ] Tester name:
- [ ] Date:
- [ ] App build/commit:
- [ ] Device 1: iPhone model + iOS version:
- [ ] Device 2: iPad model + iPadOS version:
- [ ] Locale(s) tested: `en`, `ru`
- [ ] Network modes tested: online + offline

## Preconditions

- [ ] Fresh install is successful.
- [ ] Notification permission flow appears and can be accepted/declined.
- [ ] App relaunches without crash.
- [ ] Existing data migration/upgrade path is verified (if upgrading from previous build).

## Today Screen

- [ ] Today list loads without UI freeze.
- [ ] Slot status colors are correct (`scheduled` gray, `due` orange, `missed` red, `completed` green).
- [ ] Quick BP entry saves value and updates the matching slot to completed.
- [ ] Quick glucose entry saves value and updates the matching slot to completed.
- [ ] Out-of-range BP shows alert and still allows save.
- [ ] Out-of-range glucose shows alert/inline warning and still allows save.
- [ ] Bedtime slot toggle behavior is correct when enabled/disabled.
- [ ] Daily cycle mode targets only one before-meal slot when enabled.
- [ ] App state remains correct after force-close + reopen.

## History Screen

- [ ] History opens with no crash and no layout break.
- [ ] Segment filter works (`All`, `BP`, `Glucose`).
- [ ] Range filter works (`Today`, `7 days`, `30 days`).
- [ ] Summary card values are consistent with visible entries.
- [ ] Entry timestamps and units are correct.
- [ ] Empty-state behavior is correct (no broken placeholders).

## Settings Screen

- [ ] Settings load current persisted values correctly.
- [ ] Changing thresholds/time slots is persisted after app relaunch.
- [ ] Enabling/disabling reminder groups updates scheduling behavior.
- [ ] Save action shows success/failure feedback appropriately.
- [ ] Save triggers rescheduling exactly once (no duplicate notification bursts).

## Notifications

- [ ] Scheduled notifications appear at configured times.
- [ ] Editing schedules removes outdated pending notifications.
- [ ] BP reminders are scheduled for selected weekdays only.
- [ ] Glucose reminders respect enabled kinds (before meal, after meal 2h, bedtime).
- [ ] Notification actions (`skip`, `snooze`, `move`) execute expected behavior.

## Google Sync (Offline/Online)

- [ ] Google connection can be enabled/configured in Settings.
- [ ] Online sync succeeds for pending measurements.
- [ ] Offline attempt fails gracefully (no crash, clear status/error).
- [ ] Returning online retries/recovers and marks successful sync.
- [ ] Failed records can transition to success after retry.

## CSV Export / Share

- [ ] CSV export completes without error.
- [ ] File includes expected headers and values.
- [ ] Units and timestamps in CSV are correct.
- [ ] Share sheet opens and can share/save file.

## Localization (Critical)

- [ ] Russian UI has no English leftovers in core flows (Today/History/Settings).
- [ ] English UI has no Russian leftovers in core flows.
- [ ] Mixed-language content from meal/type labels is not present.
- [ ] Date/time formatting follows locale.
- [ ] Tab titles, filter labels, alerts, buttons, and status labels are localized.

## Visual / Accessibility

- [ ] Layout is correct on iPhone portrait.
- [ ] Layout is correct on iPad portrait.
- [ ] Dynamic Type does not truncate critical controls/text.
- [ ] Light and Dark appearance are readable and consistent.

## Regression Sign-off

- [ ] No blocker issues found.
- [ ] No high-severity issues found.
- [ ] Any non-blocking issues are documented with owner.
- [ ] Ready to tag release candidate.

## Notes

- Issues found:
- Follow-ups created:
