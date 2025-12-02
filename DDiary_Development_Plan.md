
# DDiary — Development Plan

This plan is designed both for manual development and for guiding Xcode AI step by step.

---

## Phase 1 — Project Initialization

**Goals:**

- Create the base Xcode project for iOS 26+ and iPadOS 26+.
- Configure SwiftData with CloudKit.
- Set up basic targets for Unit tests and UI tests.
- Add required dependencies (if using SwiftPM for e.g. Amplitude SDK).

**Main tasks:**

1. Create a new SwiftUI app project `DDiary`.
2. Set platform deployment targets to iOS 26, iPadOS 26.
3. Enable SwiftData in the project and configure a shared model container.
4. Add test targets:
   - `DDiaryTests` (unit tests)
   - `DDiaryUITests` (UI tests)
5. Enable strict concurrency checks (Swift 6) in build settings if not enabled by default.
6. Configure bundle identifiers, signing, iCloud capability (for CloudKit).

---

## Phase 2 — Data Models & Persistence

**Goals:**

- Implement SwiftData `@Model` types for:
  - `BPMeasurement`
  - `GlucoseMeasurement`
  - `UserSettings`
  - `GoogleIntegration`
  - Supporting enums (GlucoseUnit, GlucoseMeasurementType, MealSlot, GoogleSyncStatus)
- Ensure enums are `Sendable` so they can safely cross actor boundaries, while `@Model` types remain main-actor-isolated.

**Main tasks:**

1. Define enums and models as per the technical spec:
   - Mark enums that may appear in DTOs or cross-actor messages as `Sendable`.
   - Treat all SwiftData `@Model` types as **main-actor-bound** (they must not cross actor boundaries).
2. Organize all models inside a `Models` group/module.
3. Run the app to initialize the persistent store.
4. Add a simple unit test that creates and fetches a sample measurement on the main actor.

---

## Phase 3 — Repository Layer

**Goals:**

- Define repository protocols with `async` methods.
- Split repositories into **MainActor SwiftData repositories** and **Sendable infrastructure repositories**.

**Main tasks:**

1. Create repository protocols and divide them by concurrency domain:

   **MainActor (SwiftData) repositories:**
   - `MeasurementsRepository`
   - `SettingsRepository`
   - `GoogleIntegrationRepository`

   **Sendable infrastructure repositories:**
   - `NotificationsRepository`
   - `AnalyticsRepository`
   - `GoogleSheetsClient` (later)

2. Define protocols with correct isolation:
   - SwiftData repositories must be declared as `@MainActor`.
   - Infrastructure repositories must be `Sendable`.

3. Implement repositories:
   - `SwiftDataMeasurementsRepository` — `@MainActor`.
   - `SwiftDataSettingsRepository` — `@MainActor`.
   - `SwiftDataGoogleIntegrationRepository` — `@MainActor`.
   - `UserNotificationsRepository` — conforms to `NotificationsRepository` (`Sendable`).
   - `AmplitudeAnalyticsRepository` — conforms to `AnalyticsRepository` (`Sendable`).

4. Concurrency rules:
   - SwiftData-backed repos: `@MainActor`, **not Sendable**.
   - Infrastructure repos: `Sendable`, operate only on DTOs/value types.

5. Add mock implementations:
   - MainActor mocks for SwiftData repos.
   - Sendable mocks/actors for infrastructure repos.

---

## Phase 4 — Use Cases (Actors & MainActor)

**Goals:**

- Implement use cases with a clear split:
  - `@MainActor` classes for logic involving SwiftData.
  - `actor` types only where dependencies are `Sendable` and no SwiftData is accessed.

**Main tasks:**

1. Classify use cases:

   **MainActor use cases (SwiftData-bound):**
   - `LogBPMeasurementUseCase`
   - `LogGlucoseMeasurementUseCase`
   - `GetTodayOverviewUseCase`
   - `UpdateSchedulesUseCase`
   - `RescheduleGlucoseCycleUseCase`
   - `SyncWithGoogleUseCase` (recommended MainActor variant)

   **Actor-based use cases (Sendable-only environments):**
   - `ExportCSVUseCase` (optional as actor)

2. Follow rules:
   - MainActor use cases depend on `@MainActor` repositories and `Sendable` infrastructure services.
   - Actor use cases must store only `Sendable` dependencies and accept/return only Sendable DTOs.

3. Examples:
   ```swift
   @MainActor
   final class LogBPMeasurementUseCase { ... }

   actor ExportCSVUseCase { ... }
   ```

4. Testing:
   - MainActor use cases tested on the main actor.
   - Actor use cases tested with async tests and Sendable mocks.

---

## Phase 5 — Manual DI and App Container

**Goals:**

- Provide dependency injection through an `@MainActor` container.
- Ensure proper isolation for repositories and use cases.

**Main tasks:**

1. Implement `AppContainer` as an `@MainActor` type that:
   - Owns SwiftData components.
   - Instantiates repositories and use cases.
   - Ensures actor use cases receive only Sendable dependencies.

2. Container layout:
   ```swift
   @MainActor
   struct AppContainer {
       let measurementsRepository: MeasurementsRepository
       let settingsRepository: SettingsRepository
       let googleIntegrationRepository: GoogleIntegrationRepository

       let notificationsRepository: NotificationsRepository
       let analyticsRepository: AnalyticsRepository
       let googleSheetsClient: GoogleSheetsClient

       let logBPMeasurement: LogBPMeasurementUseCase
       let logGlucoseMeasurement: LogGlucoseMeasurementUseCase
       let getTodayOverview: GetTodayOverviewUseCase
       let updateSchedules: UpdateSchedulesUseCase
       let rescheduleGlucoseCycle: RescheduleGlucoseCycleUseCase
       let syncWithGoogle: SyncWithGoogleUseCase
       let exportCSV: ExportCSVUseCase
   }
   ```

3. Use `AppEnvironment` or similar to expose the container.

4. Ensure actor isolation rules:
   - No actor stores SwiftData repos.
   - Only MainActor use cases interact with SwiftData.

---

## Phase 6 — UI Skeleton (Screens & Navigation)

**Goals:**

- Build SwiftUI ViewModels correctly isolated under `@MainActor`.
- Ensure ViewModels interact safely with use cases.

**Main tasks:**

1. Implement screens:
   - `TodayView`
   - `HistoryView`
   - `SettingsView`

2. Implement ViewModels as `@Observable` and `@MainActor`:
   ```swift
   @MainActor
   final class TodayViewModel: ObservableObject { ... }
   ```

3. Concurrency interactions:
   - Call MainActor use cases directly.
   - When calling actor-based use cases, pass only Sendable data.

4. Implement tab/navigation structure.

---

## Phase 7 — Notifications & Scheduling Logic

**Goals:**

- Implement local notifications scheduling using async wrappers around `UNUserNotificationCenter`.

**Main tasks:**

1. Expand `NotificationsRepository` with async methods for scheduling and canceling notifications.
2. Implement these methods in `UserNotificationsRepository` using async APIs or async wrappers.
3. Integrate scheduling logic with `UserSettings` and use cases:
   - Scheduling BP notifications based on `UserSettings`.
   - Scheduling glucose notifications (before meals, after meals, bedtime).
   - Handling snooze and skip actions.
   - Handling “move to lunch/dinner” for before-meal glucose.
4. Integrate notifications handling into `TodayViewModel` and Use Cases.
5. Ensure handling of notification responses updates state on the main actor.

---

## Phase 8 — Google Sheets Integration

**Goals:**

- Implement push-only Google Sheets sync using async networking.
- Keep all SwiftData interactions on the main actor.

**Main tasks:**

1. Implement OAuth flow via `ASWebAuthenticationSession` (UI → MainActor).

2. Implement a Sendable `GoogleSheetsClient` with async methods.

3. Add token refresh helper methods.

4. Implement `SyncWithGoogleUseCase` as an `@MainActor final class`:
   - Fetch pending/failed measurements from repositories.
   - Map models → Sendable DTO rows.
   - Call `GoogleSheetsClient`.
   - Update sync status using MainActor repositories.

5. Connect sync triggers to `SettingsViewModel`.

---

## Phase 9 — CSV Export

**Goals:**

- Export CSV safely without crossing actor boundaries with SwiftData models.

**Main tasks:**

1. Implement CSV export via one of two patterns:

   **Variant A — MainActor use case (recommended for v1):**
   - Fetch models using SwiftData repos.
   - Convert to Sendable DTOs.
   - Run heavy CSV string/file building inside `Task.detached`.

   **Variant B — actor use case:**
   - Provide only Sendable DTOs to the actor.
   - Actor handles CSV creation.

2. Integrate output with a share sheet.

3. Ensure no SwiftData `@Model` leaves the main actor.

---

## Phase 10 — Polishing, Localization & UX

**Goals:**

- Finalize UX, colors, and localization, ensure concurrency correctness in UI.

**Main tasks:**

1. Use system colors for status indicators (green/orange/red/gray).
2. Ensure all ViewModels are `@MainActor` and only call actors via async methods.
3. Ensure support for dark mode and Dynamic Type.
4. Add `.xcstrings` catalogs for English and Russian localization.
5. Localize UI strings.
6. Add About/Disclaimer text.

---

## Phase 11 — Testing

**Goals:**

- Provide concurrency-correct test coverage.

**Main tasks:**

1. Unit tests:
   - MainActor use cases tested on main actor.
   - Actor-based use cases tested with async tests, Sendable mocks.

2. Repository tests:
   - SwiftData repos tested with in-memory stores.
   - Sendable repos tested for concurrency correctness.

3. UI tests:
   - Validate main flows follow expected behavior.
   - Ensure no UI blocking during async operations.

---

## Phase 12 — Pre-release Checklist

**Goals:**

- Validate Swift 6 concurrency safety.

**Main tasks:**

1. Ensure no concurrency warnings remain.
2. Confirm all SwiftData interactions occur on `@MainActor`.
3. Confirm no actor stores SwiftData repos or `@Model` types.
4. Validate offline/online robustness for Google sync.
5. Perform manual QA on iPhone and iPad.
