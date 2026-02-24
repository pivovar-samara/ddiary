# DIA-ry Public Release Plan

Status date: 2026-02-21  
Scope: iOS/iPadOS public App Store release

This plan is ordered by dependency. Do not skip phases.

## Ownership model

- `Me (agent)` means I can do it directly in this repository.
- `You` means it requires your Apple account, legal/product decision, or external system access.
- `Both` means I prepare artifacts and you finalize in external systems.

## Phase 0: Blockers (must be green first)

### 0.1 Release configuration and secrets wiring
- Owner: `Me`
- Status: `Done`
- Outcome:
  - Environment-specific redirect scheme and support email are wired through xcconfigs and Info.plist.
  - CI pre-build script now enforces required env vars and generates `Configs/Secrets.xcconfig`.

### 0.2 OAuth redirect hardening
- Owner: `Me`
- Status: `Done`
- Outcome:
  - OAuth redirect URI now resolves from config with safe fallbacks.
  - Placeholder values are sanitized.
  - Presentation anchor fallback no longer loops indefinitely.

### 0.3 Align push capability surface with CloudKit sync
- Owner: `Me`
- Status: `Done`
- Outcome:
  - Kept `UIBackgroundModes=remote-notification` in Info.plist for CloudKit push-driven sync.
  - Added `aps-environment` entitlement wiring for Debug/Release builds.
  - App capabilities now match the current SwiftData + CloudKit sync model.

### 0.4 Deterministic test execution
- Owner: `Me`
- Status: `Done`
- Outcome:
  - `DDiaryTests` scheme has explicit build entries.
  - Added `ci_scripts/ci_test_unit.sh` with explicit simulator destination.
  - Verified with:
    - `xcodebuild -project DDiary.xcodeproj -scheme DDiary -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' build`
    - `xcodebuild test -scheme DDiaryTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
    - `./ci_scripts/ci_test_unit.sh`

## Phase 1: Compliance and store readiness

### 1.1 Privacy policy + support URLs
- Owner: `You`
- Deliverables:
  - Public privacy policy URL.
  - Public support URL.
  - Optional terms URL.
- Why: App Store submission fields require this and reviewers check consistency.

### 1.2 App Privacy nutrition labels (App Store Connect)
- Owner: `You`
- Deliverables:
  - Accurate declaration of health-related and analytics data use.
  - Data linkage/tracking declarations aligned with actual SDK behavior.
- Why: Mismatch can trigger rejection.

### 1.3 In-app legal copy alignment
- Owner: `Both`
- `Me`: add/adjust in-app legal text screens and disclaimers if needed.
- `You`: approve final wording.
- Why: health logging apps need clear non-medical disclaimer and data handling wording.

### 1.4 Privacy manifest decision
- Owner: `Both`
- `Me`: add app-level `PrivacyInfo.xcprivacy` if your policy requires explicit declarations beyond SDK manifests.
- `You`: confirm legal position for data categories and reason APIs.
- Why: reduces review friction and future compliance risk.

## Phase 2: Product quality gates

### 2.1 Manual QA full pass
- Owner: `You`
- Source checklist: `MANUAL_QA_CHECKLIST.md`
- Required:
  - iPhone + iPad run.
  - `en` + `ru` localization checks.
  - online/offline sync checks.

### 2.2 Release regression automation baseline
- Owner: `Me`
- Actions:
  - Keep unit tests stable and green.
  - Add one focused UI smoke flow if you want extra safety around Today quick-entry and notifications.

### 2.3 Crash and observability setup
- Owner: `Both`
- `Me`: integrate/verify crash reporter SDK if you choose one.
- `You`: create service project, provide keys, and set alert routing.
- Why: required for safe post-release response.

## Phase 3: Release candidate and submission

### 3.1 Release branch and versioning
- Owner: `Both`
- `Me`: prepare changelog notes and code freeze PR.
- `You`: choose final version/build numbers and release date.

### 3.2 Archive and upload
- Owner: `You`
- Steps:
  - Create Release archive in Xcode.
  - Validate and upload to App Store Connect.
  - Resolve signing/profile issues if any.

### 3.3 App Store metadata package
- Owner: `You`
- Deliverables:
  - Final screenshots (iPhone + iPad).
  - Subtitle/description/keywords.
  - Age rating and category.
  - Support/privacy URLs.

### 3.4 Review submission and phased rollout
- Owner: `You`
- Steps:
  - Submit for review.
  - Use phased release (recommended).
  - Monitor crashes, sync errors, and user feedback during first 7 days.

## Phase 4: Immediate post-release operations (first 7 days)

### 4.1 Daily triage window
- Owner: `Both`
- `Me`: can prepare issue triage template and hotfix checklist.
- `You`: run daily review of crashes, ratings, and support tickets.

### 4.2 Hotfix criteria
- Owner: `You`
- Rule:
  - Release hotfix immediately for data loss, sync corruption, startup crash, or notification failures.

## Ready-to-execute next actions (in order)

1. `You`: provide final support email + privacy policy URL.
2. `You`: complete App Privacy labels in App Store Connect.
3. `You`: execute `MANUAL_QA_CHECKLIST.md` on physical iPhone + iPad.
4. `Me`: after your QA notes, fix remaining issues and prepare RC branch.
5. `You`: archive, upload, and submit for App Review.
