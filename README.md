## Summary

DDiary is a personal health tracking app for iOS and iPadOS that helps users log:

- Blood pressure (systolic, diastolic) and pulse.
- Blood glucose, with context relative to meals.

Key goals:

- Extremely **fast and low-friction data entry**, especially around notification reminders.
- **Configurable schedules** for blood pressure and glucose measurement.
- **Local-first** storage with **SwiftData** and transparent sync across user devices via **iCloud/CloudKit**.
- Optional **push-only backup to Google Sheets** as a secondary, desktop-accessible data channel.
- Production-ready architecture suitable for extension in v2 (graphs, analytics, integrations).

The app is explicitly **not a medical device** and provides no medical recommendations.

---

## 1. Platforms, Tools & Constraints

- **Target platforms:**  
  - iOS 26+ (iPhone)  
  - iPadOS 26+
- **Language:** Swift 6.2
- **UI framework:** SwiftUI
- **Persistence:** SwiftData with CloudKit sync enabled.
- **Networking / APIs:** URLSession (or similar standard) for Google Sheets integration.
- **Architecture:** MVVM + Use Case + Repository + manual DI.
- **Use Cases:** Implemented as `actor`s.
- **Domain vs Persistence models:** SwiftData `@Model` types double as domain models (Option B).
- **Analytics:** Amplitude (minimal events).
- **Tests:** Unit tests, repository tests with mocks, and basic UI tests.

Apple Health integration is intentionally **excluded from v1**.

---

## 2. Domain Model

All models below are SwiftData `@Model` types (domain + persistence).

### 2.1 Blood Pressure Measurement (`BPMeasurement`)

Represents a single blood pressure + pulse measurement.

Fields:

- `id: UUID`
- `timestamp: Date`
- `systolic: Int`
- `diastolic: Int`
- `pulse: Int`
- `comment: String?`
- `googleSyncStatus: GoogleSyncStatus`
- `googleLastError: String?`
- `googleLastSyncAt: Date?`

### 2.2 Glucose Measurement (`GlucoseMeasurement`)

Represents a single blood glucose measurement.

Enums:

```swift
enum GlucoseUnit: String, Codable {
    case mmolL   // mmol/L
    case mgdL    // mg/dL
}

enum GlucoseMeasurementType: String, Codable {
    case beforeMeal
    case afterMeal2h
    case bedtime
}

enum MealSlot: String, Codable {
    case breakfast
    case lunch
    case dinner
    case none     // for bedtime or other non-meal cases
}
```

Model fields:

- `id: UUID`
- `timestamp: Date`
- `value: Double`
- `unit: GlucoseUnit`
- `measurementType: GlucoseMeasurementType`
- `mealSlot: MealSlot`
- `comment: String?`
- `googleSyncStatus: GoogleSyncStatus`
- `googleLastError: String?`
- `googleLastSyncAt: Date?`

### 2.3 Google Sync Status (`GoogleSyncStatus`)

Represents the sync state of a measurement with Google Sheets.

```swift
enum GoogleSyncStatus: String, Codable {
    case pending
    case success
    case failed
}
```

### 2.4 User Settings (`UserSettings`)

Application-wide user preferences and schedules. There is normally a single instance per user.

Fields (simplified, can be expanded in implementation):

- Identity:
  - `id: UUID`
- Units:
  - `glucoseUnit: GlucoseUnit`
- Blood pressure thresholds:
  - `bpSystolicMin: Int`
  - `bpSystolicMax: Int`
  - `bpDiastolicMin: Int`
  - `bpDiastolicMax: Int`
- Glucose thresholds:
  - `glucoseMin: Double`
  - `glucoseMax: Double`
- Meal times (local time components, no date):
  - `breakfastTime: DateComponents` (hour, minute)
  - `lunchTime: DateComponents`
  - `dinnerTime: DateComponents`
  - `bedtimeSlotEnabled: Bool`
- Blood pressure reminder schedule:
  - `bpTimes: [DateComponents]` (list of times in a day, e.g., 09:00, 22:00)
  - `bpActiveWeekdays: Set<Int>` (1–7, Sunday or Monday based depending on convention, implementation detail)
- Glucose reminders:
  - `enableBeforeMeal: Bool`
  - `enableAfterMeal2h: Bool`
  - `enableBedtime: Bool`
  - `enableDailyCycleMode: Bool` (if using a 1-slot-per-day cycle across breakfast/lunch/dinner/bedtime)
  - `currentCycleIndex: Int` (0–3 if cycle is breakfast → lunch → dinner → bedtime)

### 2.5 Google Integration (`GoogleIntegration`)

Represents Google Sheets configuration. Stored as SwiftData model and synced via CloudKit so multiple devices share the same integration.

Fields:

- `id: UUID`
- `spreadsheetId: String?`
- `googleUserId: String?`
- `refreshToken: String?`
- `isEnabled: Bool`

---

## 3. Schedules, Slots and Statuses

The app models daily “slots” for measurements. These are conceptual and mostly expressed in:

- Scheduled notification times.
- UI representation of the “Today” screen.
- Logic for “missed / due / completed” status and cycle mode.

### 3.1 Slot Status Rules

For a given scheduled slot (BP or glucose) with planned time `slotTime`:

- **scheduled (grey)** — `now < slotTime`
- **due (orange)** — `slotTime <= now <= slotTime + 2 hours`
- **missed (red)** — `now > slotTime + 2 hours` and no measurement logged for this logical slot.
- **completed (green)** — a measurement was logged for this logical slot on this date (regardless of exact timestamp, as long as it corresponds to the intended type/slot).

“Completed” always overrides “missed”/“due” once a measurement exists (for that slot/day).

### 3.2 “Today” Status

On the Today screen:

- Each BP reminder slot shows status color based on the rules above.
- Each glucose slot (breakfast before/after, lunch before/after, dinner before/after, bedtime) similarly shows status.
- Overall card color can be:

  - **Green** — all active slots for today are completed.
  - **Orange/Grey** — at least one active slot is scheduled or due, and none are missed yet.
  - **Red** — at least one active slot is missed.

Implementation details of the “overall color” are flexible; the important part is that individual slot statuses are correct.

### 3.3 Daily Glucose Cycle Mode

Optional mode: “1 glucose measurement per day” cycling across meal slots.

Cycle sequence:

```text
breakfast → lunch → dinner → bedtime → breakfast → ...
```

Logic:

- `currentCycleIndex` in `UserSettings` indicates which slot is targeted for the current day.
- If user logs **any** glucose measurement for a different slot than the current cycle slot:
  - The actual logged `mealSlot` and `measurementType` are respected.
  - After logging, the cycle should advance in a way that “skips” already measured slots.
  - Example (simplified):
    - Day 1 target: breakfast.
    - User logs lunch instead.
    - Cycle considers lunch “covered”.
    - Next day’s plan: breakfast, then dinner (depending on chosen algorithm), but details can be refined during implementation.
- If user logs **no** glucose measurement for a given day:
  - `currentCycleIndex` stays the same and is reused for the next day.

The cycle mode is optional and can be implemented in a minimal way in v1; the core requirement is to support:

- 1 slot per day tracking mode.
- Ability to shift/preserve the target slot depending on user behavior.

---

## 4. Notifications and Quick Entry

### 4.1 General Principles

- Local notifications are scheduled for:

  - Blood pressure time slots (from `bpTimes` and `bpActiveWeekdays`).
  - Glucose measurement times (meal times, before meals, bedtime, and cycle mode if enabled).

- Notifications **do not** contain inline text fields. Instead, they have actions that open the app to a **Quick Entry screen**.

### 4.2 Notification Actions

#### 4.2.1 For Blood Pressure

Actions:

- **Enter** — opens Quick Entry for BP (SYS/DIA/Pulse, comment).
- **Snooze** — offers choices (e.g., 15 / 30 / 60 minutes), rescheduling a notification.
- **Skip** — marks the slot as conceptually “missed” for the day.

#### 4.2.2 For Glucose — Before Meal

When the notification corresponds to a “before meal” glucose measurement:

- **Enter** — opens Quick Entry for glucose with:

  - `measurementType = .beforeMeal`
  - `mealSlot = breakfast/lunch/dinner` (as per context)

- **Move to lunch** / **Move to dinner** (exact labels depend on current meal slot):
  - If the notification is “before breakfast”, show:

    - `Move to lunch`
    - `Move to dinner`

  - Choosing one of these updates the **daily plan**: the target slot for today is changed to lunch or dinner; a new notification is scheduled at the corresponding meal time. The original breakfast slot is not marked as missed.
- **Snooze** — as above.
- **Skip** — marks the planned slot as missed for the day.

#### 4.2.3 For Glucose — After Meal (2h) or Bedtime

Actions:

- **Enter** — opens Quick Entry with appropriate `measurementType` and `mealSlot` pre-set.
- **Snooze**
- **Skip**

“Move to lunch/dinner” is not shown for after-meal or bedtime notifications.

---

## 5. Quick Entry Screens

### 5.1 BP Quick Entry

Fields:

- Systolic (numeric)
- Diastolic (numeric)
- Pulse (numeric)
- Comment (optional, multiline or single line)

Constraints:

- Only basic numeric validation (e.g. not empty when required).
- No enforcement of medical “valid ranges” in v1.

Actions:

- Cancel
- Save

On Save:

- Create a `BPMeasurement` with current `Date` (or a passed-in slot-based timestamp if needed).
- Set `googleSyncStatus = .pending`.
- Trigger local notifications recomputation if necessary.

### 5.2 Glucose Quick Entry

Fields:

- Value (numeric)
- Unit (taken from `UserSettings.glucoseUnit`, not editable per entry in v1)
- Comment (optional)
- `measurementType` and `mealSlot` are normally passed in from the context (Today screen or notification). They may be visible in the UI as labels rather than editable fields.

On Save:

- Create `GlucoseMeasurement`.
- Set `googleSyncStatus = .pending`.
- Possibly update cycle index / plan if in daily cycle mode.
- Trigger local notifications recomputation if necessary.

---

## 6. Screens & Flows

### 6.1 Today Screen

Purpose: main operational screen for daily use.

Sections:

1. **Blood Pressure Card**
   - Shows:
     - Next BP measurement time.
     - Latest BP measurement.
     - List of today’s BP slots with status colors (grey/orange/red/green).
   - Interactions:
     - Tap a slot → open Quick Entry for BP.
     - Optional button “Measure now” to open Quick Entry (not bound to a specific slot).

2. **Glucose Card**
   - Shows:
     - List of glucose slots for today:

       - Breakfast before
       - Breakfast after 2h
       - Lunch before
       - Lunch after 2h
       - Dinner before
       - Dinner after 2h
       - Bedtime (if enabled)

     - Each with status color.
   - Interactions:
     - Tap slot → open Quick Entry for glucose, with pre-set context.

### 6.2 History Screen

Purpose: view past data and simple aggregates (no graphs in v1).

Features:

- Filter by:
  - Type: BP / Glucose / Both.
  - Date range: today / last 7 days / last 30 days / custom.
- Display:
  - Table-style list of entries:
    - For BP: date, time, SYS/DIA, pulse, comment.
    - For glucose: date, time, value, unit, measurementType, mealSlot, comment.
- Aggregates:
  - For the selected period:
    - Count of measurements.
    - Min / max / average for relevant numeric values.

### 6.3 Settings Screen

Sections:

1. **Units**
   - Glucose unit selection (`mmol/L` or `mg/dL`).

2. **Meal Times**
   - Breakfast time.
   - Lunch time.
   - Dinner time.
   - Toggle for bedtime slot.

3. **Blood Pressure Reminders**
   - List of times in a day (add/remove).
   - Weekday selection (e.g. checkboxes).

4. **Glucose Reminders**
   - Toggles:
     - Before meals.
     - After meals (2h).
     - Bedtime.
     - Daily cycle mode.

5. **Thresholds**
   - BP min/max SYS and DIA.
   - Glucose min/max.

6. **Google Sheets Backup**
   - Status:
     - Connected (show email or user id).
     - Not connected.
   - Connect button:
     - Begins OAuth flow, obtains tokens, sets up sheet.
   - Disconnect button:
     - Clears `refreshToken`, sets `isEnabled = false`, stops further sync attempts.
   - General sync info / last sync summary.

7. **Export**
   - Export to CSV:
     - Date range.
     - Types (BP, Glucose).
     - Use iOS share sheet to export file.

8. **Feedback & About**
   - Open email composer with prefilled subject/body and basic debug info (device, iOS version, app version).
   - Show disclaimer text and basic app info.

### 6.4 CSV Export Format

For BP:

Columns:

- `timestamp` (ISO 8601)
- `date` (YYYY-MM-DD)
- `time` (HH:mm)
- `systolic`
- `diastolic`
- `pulse`
- `comment`
- `id`

For Glucose:

- `timestamp`
- `date`
- `time`
- `value`
- `unit`
- `measurementType`
- `mealSlot`
- `comment`
- `id`

Encoding: UTF-8, delimiter: `,` (comma; or `;` for regional preferences as needed).

---

## 7. Google Sheets Integration

### 7.1 Authentication

- Use OAuth via `ASWebAuthenticationSession`.
- Required scope: read/write access to Google Sheets for a single spreadsheet.
- Store:
  - `refreshToken` (secure).
  - `googleUserId` if available.
  - `spreadsheetId`.

These fields live in `GoogleIntegration` and are synced across devices via SwiftData+CloudKit.

### 7.2 Spreadsheet Structure

Single spreadsheet with at least two sheets:

- **`BP`**:
  - Columns: `timestamp`, `date`, `time`, `systolic`, `diastolic`, `pulse`, `comment`, `id`.

- **`Glucose`**:
  - Columns: `timestamp`, `date`, `time`, `value`, `unit`, `measurementType`, `mealSlot`, `comment`, `id`.

Column names in **English** for easier programmatic handling.

### 7.3 Sync Strategy (Push-only)

- Every new or updated measurement has a `googleSyncStatus` field:
  - When created: set to `.pending` if Google integration is enabled.
- Sync worker (can be triggered on app start, on network availability, or periodically):

  - Finds all measurements with `.pending` or `.failed`.
  - For each:
    - Attempts to append a row to the appropriate sheet.
    - On success:
      - `googleSyncStatus = .success`
      - `googleLastError = nil`
      - `googleLastSyncAt = now`
    - On error:
      - `googleSyncStatus = .failed`
      - `googleLastError` set to error description
      - `googleLastSyncAt = now`

- Settings screen should surface a simple summary, e.g.:

  - “Google Sheets: connected, X unsynced entries (last error: …)”
  - Retry button to force sync.

### 7.4 Logout / Disconnect

When user taps “Disconnect Google”:

- Set `isEnabled = false`.
- Clear `refreshToken`.
- Optionally clear `spreadsheetId` and `googleUserId` (depending on desired behavior).
- No further sync attempts are made.
- Existing `success`/`failed` flags remain for history; `pending` entries might remain but won’t be synced until integration is re-enabled.

---

## 8. Sync Between Devices (iCloud/CloudKit)

- SwiftData is configured with CloudKit-backed persistent container.
- All `@Model` entities (`BPMeasurement`, `GlucoseMeasurement`, `UserSettings`, `GoogleIntegration`) are synced via the private iCloud database.
- When a measurement is synced across devices, its `googleSyncStatus` is also synced, ensuring that:

  - Any device can attempt the Google sync for a pending/failed record, but once one device succeeds and marks it `success`, others will not re-sync it.

---

## 9. Architecture

### 9.1 Layers

1. **Presentation Layer (SwiftUI + MVVM)**

   - View: SwiftUI views (`TodayView`, `HistoryView`, `SettingsView`, etc.).
   - ViewModels: `@Observable` classes holding view state and interacting with Use Cases.

2. **Domain Layer (Use Cases as actors)**

   - Use Case actors encapsulate business logic:

     - `LogBPMeasurementUseCase`
     - `LogGlucoseMeasurementUseCase`
     - `ExportCSVUseCase`
     - `SyncWithGoogleUseCase`
     - `UpdateSchedulesUseCase`
     - `RescheduleGlucoseCycleUseCase`
     - `GetTodayOverviewUseCase`
     - etc.

   - Each use case depends on repository protocols.

3. **Data Layer (Repositories)**

   - Repository protocols:

     - `MeasurementsRepository`
     - `SettingsRepository`
     - `GoogleIntegrationRepository`
     - `NotificationsRepository`
     - `AnalyticsRepository`

   - Concrete implementations:

     - `SwiftDataMeasurementsRepository`
     - `SwiftDataSettingsRepository`
     - `SwiftDataGoogleIntegrationRepository`
     - `UserNotificationsRepository`
     - `AmplitudeAnalyticsRepository`

### 9.2 Manual Dependency Injection

- There is a central `AppContainer` (or similar) responsible for wiring dependencies:

```swift
struct AppContainer {
    let measurementsRepository: MeasurementsRepository
    let settingsRepository: SettingsRepository
    let googleIntegrationRepository: GoogleIntegrationRepository
    let notificationsRepository: NotificationsRepository
    let analyticsRepository: AnalyticsRepository

    let logBPMeasurementUseCase: LogBPMeasurementUseCase
    // ... other use cases ...
}
```

- The root SwiftUI App struct constructs this container and passes dependencies into root ViewModels.

---

## 10. Testing Requirements

### 10.1 Unit Tests for Use Cases

- Each use case actor should have unit tests verifying business logic, including:

  - Correct creation and saving of measurements.
  - Proper update of `googleSyncStatus`.
  - Correct behavior of daily cycle logic.
  - Correct interaction with repositories (e.g., calling expected methods with correct parameters).

### 10.2 Repository Tests with Mocks

- Mock or stub implementations of repository protocols for testing Use Cases.
- Tests to ensure:

  - Error propagation.
  - Retries/resilience logic (e.g., Google sync).

### 10.3 UI Tests

- At least one end-to-end XCUITest scenario:

  - Launch app.
  - Open Today screen.
  - Add BP measurement.
  - Verify it appears in History.
  - Export CSV and verify file existence (as far as XCTest allows).
  - Optionally check basic navigation and Settings interactions.

---

## 11. MVP Scope

Included in v1:

- Local storage with SwiftData + CloudKit.
- Today screen with slot-based statuses and quick entry.
- History screen (list + aggregates).
- Configurable BP and glucose reminders.
- Notification actions (enter/snooze/skip/move to other meal for glucose before-meal).
- CSV export.
- Google Sheets backup (push-only).
- Manual DI, MVVM, Use Cases as actors, SwiftData models as domain models.
- Analytics integration with minimal events.
- Unit tests, basic repository tests, and minimal XCUITests.

Excluded from v1:

- Graphs and visual analytics.
- Apple Health integration.
- Advanced recommendations or medical interpretations.
- Complex multi-user sharing or doctor-facing features.
