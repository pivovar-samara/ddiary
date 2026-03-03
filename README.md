# DIA-ry

DIA-ry is a local-first iOS and iPadOS app for tracking blood pressure and blood glucose with fast daily logging, reminders, and optional Google Sheets backup.

## Getting Started

### Requirements

- Xcode 26+
- iOS/iPadOS 26+ SDK

### Local setup

1. Open the project in Xcode:
   - `DDiary.xcodeproj`
2. Create your local secrets file:
   - `cp Configs/Secrets.xcconfig.example Configs/Secrets.xcconfig`
3. Fill `Configs/Secrets.xcconfig` with your own values:
   - `GOOGLE_OAUTH_KEY_DEV`
   - `GOOGLE_OAUTH_KEY_PROD`
   - `GOOGLE_OAUTH_REDIRECT_SCHEME_DEV`
   - `GOOGLE_OAUTH_REDIRECT_SCHEME_PROD`
   - `AMPLITUDE_API_KEY_DEV`
   - `AMPLITUDE_API_KEY_PROD`
   - `SUPPORT_EMAIL_DEV`
   - `SUPPORT_EMAIL_PROD`

`Configs/Secrets.xcconfig` is intentionally gitignored and must never contain shared production credentials in commits.

Note: the user-facing app name is `DIA-ry`, while technical project identifiers (repository, Xcode target/scheme, bundle prefix) still use `DDiary`.

## Community

- Contributing guide: [CONTRIBUTING.md](CONTRIBUTING.md)
- Code of conduct: [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)
- Security policy: [SECURITY.md](SECURITY.md)
- License: [LICENSE](LICENSE) (MIT)

## Detailed Product Notes

### Summary

DIA-ry is a personal health tracking app for iOS and iPadOS that helps users log:

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
- **Language:** Swift 6.0
- **Concurrency model:** **Swift 6 concurrency** only:
  - Use `async/await`, `Task`, and `@MainActor` isolation.
  - Avoid completion-handler–style APIs internally; wrap such APIs with async adapters.
  - Make types `Sendable` where appropriate to be compatible with Swift 6 strict concurrency checks.
- **UI framework:** SwiftUI
- **Persistence:** SwiftData with CloudKit sync enabled.
- **Networking / APIs:** URLSession (or similar standard) wrapped in async `func`s.
- **Architecture:** MVVM + Use Case + Repository + **manual DI**.
- **Use Cases:** Implemented as **`@MainActor` classes** around repository operations.
- **Domain vs Persistence models:** SwiftData `@Model` types double as domain models (Option B).
- **Analytics:** Amplitude (minimal events).
- **Tests:** Unit tests, repository tests with mocks, and basic UI tests.

Apple Health integration is intentionally **excluded from v1**.

---

## 2. Domain Model

All models below are SwiftData `@Model` types (domain + persistence).  
They are used primarily from the main actor via SwiftUI and SwiftData’s `ModelContext`, so strict cross-actor Sendability is usually not required for models themselves.

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

Fields (current implementation):

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
- Meal times (stored as hour/minute integers):
  - `breakfastHour: Int`, `breakfastMinute: Int`
  - `lunchHour: Int`, `lunchMinute: Int`
  - `dinnerHour: Int`, `dinnerMinute: Int`
  - `bedtimeSlotEnabled: Bool`
  - `bedtimeHour: Int`, `bedtimeMinute: Int`
- Blood pressure reminder schedule:
  - `bpTimes: [Int]` (minutes since midnight, e.g., 09:00 -> `540`)
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

Access to `GoogleIntegration` should be coordinated through a repository on the main actor; tokens are passed into background `Task`s for networking.

---

## 3. Schedules, Slots and Statuses

The app models daily “slots” for measurements. Intended to be computed in a concurrency-safe manner, typically via `@MainActor` view models/use cases. These are conceptual and mostly expressed in:

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

The status computation is pure and can be performed in synchronous helper functions or in @MainActor view models.

### 3.2 “Today” Status

On the Today screen:

- Each BP reminder slot shows status color based on the rules above.
- Each glucose slot (breakfast before/after, lunch before/after, dinner before/after, bedtime) similarly shows status.
- Slots are presented in grouped sections (`Now`, `Later`, `Overdue`, `Completed`) with per-row status styling.

### 3.3 Daily Glucose Cycle Mode

Optional mode: “1 glucose measurement per day” cycling across meal slots.

Cycle sequence:

```text
breakfast → lunch → dinner → bedtime → breakfast → ...
```

Logic:

- `currentCycleIndex` in `UserSettings` indicates which slot is targeted for the current day.
- In current implementation, cycle targeting applies to **before-meal slots** when both `enableDailyCycleMode` and `enableBeforeMeal` are enabled.
- Cycle advances only when the user logs a `beforeMeal` entry for the **current target slot**.
- If user logs a different slot/type, `currentCycleIndex` is not advanced automatically.
- If user logs no glucose measurement, `currentCycleIndex` remains unchanged.
- All updates to `UserSettings.currentCycleIndex` are kept on `@MainActor`.

---

## 4. Notifications and Quick Entry

### 4.1 General Principles

- Local notifications are scheduled for:

  - Blood pressure time slots (from `bpTimes` and `bpActiveWeekdays`).
  - Glucose measurement times (meal times, before meals, after-meal +2h, bedtime).

- Notifications **do not** contain inline text fields. Actions currently foreground the app and trigger lightweight notification handlers.
- Interactions with `UNUserNotificationCenter` should be wrapped in async functions (e.g. using `withCheckedContinuation` if needed).
- Handling of notification responses should funnel into @MainActor methods when updating UI or SwiftData.

### 4.2 Notification Actions

#### 4.2.1 For Blood Pressure

Actions:

- **Enter** — currently foregrounds the app.
- **Snooze** — offers choices (e.g., 15 / 30 / 60 minutes), scheduling an additional one-off reminder.
- **Skip** — currently handled as a lightweight analytics action (no explicit slot mutation).

#### 4.2.2 For Glucose — Before Meal

When the notification corresponds to a “before meal” glucose measurement:

- **Enter** — currently foregrounds the app (explicit deep-link into a specific quick-entry form is not yet implemented).
- **Snooze** — as above.
- **Skip** — currently handled as a lightweight analytics action.

#### 4.2.3 For Glucose — After Meal (2h) or Bedtime

Actions:

- **Enter** — currently foregrounds the app.
- **Snooze**
- **Skip** — currently handled as a lightweight analytics action.

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

- Numeric parsing is required for Save.
- Out-of-range values are warned in UI; user can still confirm with “Save anyway”.

Actions:

- Cancel
- Save

On Save:

- Create a new `BPMeasurement` (or update an existing one in edit mode).
- Set `googleSyncStatus = .pending`.
- Post measurement-change notification for dependent UI refresh.

### 5.2 Glucose Quick Entry

Fields:

- Value (numeric)
- Unit (taken from `UserSettings.glucoseUnit`, not editable per entry in v1)
- Comment (optional)
- `measurementType` and `mealSlot` are normally passed in from the Today/History context and shown as labels.

On Save:

- Create a new `GlucoseMeasurement` (or update an existing one in edit mode).
- Set `googleSyncStatus = .pending`.
- Possibly update cycle index / plan if in daily cycle mode.
- Post measurement-change notification for dependent UI refresh.

---

## 6. Screens & Flows

Implementation should:

- Mark ViewModels as `@MainActor` (or use `@Observable` with main-actor isolation).
- Use async calls to `@MainActor` use case classes from the main thread via `Task { await useCase.execute(...) }`.

### 6.1 Today Screen

Purpose: main operational screen for daily use.

Sections:

1. **Now**
   - Unified list of due BP/Glucose slots.
2. **Later**
   - Unified list of upcoming scheduled slots.
3. **Overdue**
   - Unified list of missed slots.
4. **Completed**
   - Collapsible list (`DisclosureGroup`) of completed slots.

Interactions:
- Tap BP slot -> open BP Quick Entry (create/edit by matched measurement ID).
- Tap glucose slot -> open Glucose Quick Entry with prefilled `mealSlot` and `measurementType`.

### 6.2 History Screen

Purpose: view past data and simple aggregates (no graphs in v1).

Features:

- Filter by:
  - Type: BP / Glucose / Both.
  - Date range presets: today / last 7 days / last 30 days.
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
     - Clears `refreshToken`/`spreadsheetId`/`googleUserId`, sets `isEnabled = false`, stops further sync attempts.
   - General sync info / last sync summary.

7. **Export**
   - Export to CSV:
     - Date range.
     - Types (BP, Glucose).
     - Use iOS share sheet to export file.

8. **Feedback & About**
   - Open `mailto:` feedback action with prefilled subject.
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

Encoding: UTF-8, delimiter: `,` (comma).

---

## 7. Google Sheets Integration

- `GoogleSheetsClient` operations are `async` and are called from `SyncWithGoogleUseCase` (`@MainActor`).
- Networking runs via `URLSession`; results are persisted via main-actor repositories backed by SwiftData.

### 7.1 Authentication

- Use OAuth via `ASWebAuthenticationSession`.
- Required scope: read/write access to Google Sheets for a single spreadsheet.
- Store:
  - `refreshToken` (persisted in `GoogleIntegration`).
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

- Every new or updated measurement is set to `googleSyncStatus = .pending` in current implementation.
- Sync worker (currently triggered from Settings actions such as Connect and Sync Now):

  - Finds all measurements with `.pending` or `.failed`.
  - For each:
    - Performs upsert-by-`id` on the appropriate sheet (update existing row if found, otherwise append).
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
- Clear `refreshToken`, `spreadsheetId`, and `googleUserId`.
- No further sync attempts are made.
- Existing `success`/`failed` flags remain for history; `pending` entries might remain but won’t be synced until integration is re-enabled.

---

## 8. Sync Between Devices (iCloud/CloudKit)

- SwiftData is configured with CloudKit-backed persistent container.
- All `@Model` entities (`BPMeasurement`, `GlucoseMeasurement`, `UserSettings`, `GoogleIntegration`) are synced via the private iCloud database.
- When a measurement is synced across devices, its `googleSyncStatus` is also synced, ensuring that:
  - Any device can attempt the Google sync for a pending/failed record, but once one device succeeds and marks it `success`, others will not re-sync it.
- SwiftData + CloudKit synchronization is managed by the system; application code should avoid doing long-running work on the main actor inside SwiftUI lifecycle methods.
- Use case classes can react to changes signaled by view models (e.g. on app launch or settings change) and perform async work.


---

## 9. Architecture

### 9.1 Layers

1. **Presentation Layer (SwiftUI + MVVM)**

   - View: SwiftUI views (`TodayView`, `HistoryView`, `SettingsView`, etc.).
   - ViewModels: `@Observable` classes, typically annotated `@MainActor`, holding view state and interacting with Use Cases via `async` methods.

2. **Domain Layer (Use Cases as `@MainActor` classes)**

   - Use cases encapsulate business logic and coordinate repositories:

     - `LogBPMeasurementUseCase`
     - `LogGlucoseMeasurementUseCase`
     - `UpdateBPMeasurementUseCase`
     - `UpdateGlucoseMeasurementUseCase`
     - `ExportCSVUseCase`
     - `SyncWithGoogleUseCase`
     - `UpdateSchedulesUseCase`
     - `RescheduleGlucoseCycleUseCase`
     - `GetTodayOverviewUseCase`
     - `GetHistoryUseCase`

   - Each use case is initialized with repository protocol dependencies and runs on `@MainActor` when touching SwiftData models.

3. **Data Layer (Repository protocols + implementations)**

   - Repository protocols (expose `async` methods):

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
    
   - SwiftData-based repositories are generally used from the main actor; repository functions that mutate SwiftData should be `@MainActor` or call `MainActor.run`.
   - Networking and analytics code can run on background tasks but must coordinate writes through repos.

### 9.2 Manual Dependency Injection

- There is a central `AppContainer` (or similar) responsible for wiring:
  - Concrete repository implementations.
  - Use case classes.

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
- ViewModels receive references to use cases and repositories as needed.

---

## 10. Testing Requirements

### 10.1 Unit Tests for Use Cases

- Each use case should have unit tests verifying business logic, including:

  - Correct creation and saving of measurements.
  - Proper update of `googleSyncStatus`.
  - Correct behavior of daily cycle logic.
  - Correct interaction with repositories (e.g., calling expected methods with correct parameters).
  - Correct behavior when multiple `Task`s call the use case concurrently (where relevant).
  - Correct state transitions on `googleSyncStatus`.

- Use `async` test methods.
- Use mock repositories that conform to protocols and are safe for main-actor usage in tests.

### 10.2 Repository Tests with Mocks

- Mock or stub implementations of repository protocols for testing Use Cases.
- Repository logic touching SwiftData may be tested on @MainActor.
- Mock repositories for use cases can be simple test doubles, depending on test design.
- Tests to ensure:

  - Error propagation.
  - Retries/resilience logic (e.g., Google sync).

### 10.3 UI Tests

- Existing UI test coverage includes:

  - Launch and basic performance test.
  - Today quick-entry flow for BP and glucose with History verification.
  - Out-of-range BP warning flow.
  - Out-of-range glucose warning + inline validation flow.
  - Bedtime slot toggle behavior reflected on Today screen.

---

## 11. MVP Scope

Included in v1:

- Local storage with SwiftData + CloudKit.
- Today screen with slot-based statuses and quick entry.
- History screen (list + aggregates).
- Configurable BP and glucose reminders.
- Notification actions (snooze/skip; `enter` currently foregrounds the app).
- CSV export.
- Google Sheets backup (push-only).
- Manual DI, MVVM, `@MainActor` use case classes, SwiftData models as domain models.
- Analytics integration with minimal events.
- Unit tests, basic repository tests, and minimal XCUITests.
- Prefer `async/await` over callbacks.
- Use main-actor isolation and `Sendable` boundaries for domain and repository logic.
- Keep heavy work off the main actor while ensuring SwiftData and SwiftUI interactions happen on the main actor.

Excluded from v1:

- Graphs and visual analytics.
- Apple Health integration.
- Advanced recommendations or medical interpretations.
- Complex multi-user sharing or doctor-facing features.
