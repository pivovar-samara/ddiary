# AGENTS.md

Guidance for coding agents working in this repository.
Scope: entire repo.

## Project Snapshot

- Platform: iOS/iPadOS 26+
- Language: Swift 6
- UI: SwiftUI + Observation
- Persistence: SwiftData (+ CloudKit in normal app mode)
- Architecture: MVVM + UseCase + Repository + manual DI (`AppContainer`)
- Xcode project: `DDiary.xcodeproj`
- Main app scheme: `DDiary`
- Test schemes: `DDiaryTests`, `DDiaryUITests`

## Local Setup

1. Create secrets file:
   - `cp Configs/Secrets.xcconfig.example Configs/Secrets.xcconfig`
2. Fill values in `Configs/Secrets.xcconfig` (do not commit this file).
3. Open `DDiary.xcodeproj` in Xcode 26+.

## Build / Test / Lint Commands

Use this simulator destination unless you need a different one:

- `DEST="platform=iOS Simulator,OS=26.2,name=iPhone 17 Pro"`

### Build

- Build app scheme:
  - `xcodebuild build -project DDiary.xcodeproj -scheme DDiary -destination "$DEST"`
- Build unit-test scheme:
  - `xcodebuild build -project DDiary.xcodeproj -scheme DDiaryTests -destination "$DEST"`

### Test (common)

- Run unit tests (matches CI helper script intent):
  - `xcodebuild test -project DDiary.xcodeproj -scheme DDiaryTests -destination "$DEST" -destination-timeout 180 -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1`
- Run minimal PR plan:
  - `xcodebuild test -project DDiary.xcodeproj -scheme DDiary -testPlan DDiaryMinimal -destination "$DEST" -destination-timeout 180 -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1`
- Run CI plan (unit + launch UI test):
  - `xcodebuild test -project DDiary.xcodeproj -scheme DDiary -testPlan DDiaryCITests -destination "$DEST"`
- Run full plan (unit + UI):
  - `xcodebuild test -project DDiary.xcodeproj -scheme DDiary -testPlan DDiaryFull -destination "$DEST"`

### Run a Single Test (important)

- Single test method:
  - `xcodebuild test -project DDiary.xcodeproj -scheme DDiaryTests -destination "$DEST" -only-testing:DDiaryTests/LogBPMeasurementUseCaseTests/test_happyPath_insertsAndLogsAnalytics`
- Single test class:
  - `xcodebuild test -project DDiary.xcodeproj -scheme DDiaryTests -destination "$DEST" -only-testing:DDiaryTests/LogBPMeasurementUseCaseTests`
- Single UI test method:
  - `xcodebuild test -project DDiary.xcodeproj -scheme DDiaryUITests -destination "$DEST" -only-testing:DDiaryUITests/DDiaryUITestsLaunchTests/testLaunch`

### Lint / Static Checks

- There is no SwiftLint/SwiftFormat config in this repo currently.
- Treat these as baseline quality gates:
  - `xcodebuild build -project DDiary.xcodeproj -scheme DDiary -destination "$DEST"`
  - `xcodebuild analyze -project DDiary.xcodeproj -scheme DDiary -destination "$DEST"`
- If a future PR adds SwiftLint/SwiftFormat config, follow that config as source of truth.

### CI Scripts

- Unit-test script: `ci_scripts/ci_test_unit.sh`
- CI secrets pre-step: `ci_scripts/ci_pre_xcodebuild.sh`
- PR workflow: `.github/workflows/pr-ddiary-minimal.yml`

## Code Style and Conventions

### Imports

- Keep imports minimal and explicit.
- Common order used in repo: Apple frameworks first (`SwiftUI`, `SwiftData`, `Foundation`, `Observation`, etc.).
- `@testable import DDiary` is used in test targets.

### Formatting

- Follow existing Swift formatting; do not introduce a new style.
- Use `// MARK:` sections in longer files.
- Prefer descriptive multi-line initializers/calls over dense one-liners.
- Keep trailing whitespace out; keep files ASCII unless there is clear reason otherwise.

### Types and Architecture

- Prefer `struct` for value types and SwiftUI views; `final class` for mutable reference types (view models/use cases as appropriate).
- View models are typically `@MainActor` + `@Observable`.
- Use cases are typically `@MainActor` classes that orchestrate repositories.
- Repository protocols:
  - SwiftData-backed repositories are `@MainActor`.
  - Infra repositories may be `Sendable` and actor-independent.
- Prefer protocol-based dependencies with manual DI via `AppContainer`.
- Use `any ProtocolName` existential style when storing protocol-typed dependencies (consistent with current codebase).

### Concurrency

- Swift 6 concurrency style only (`async/await`, `Task`, actors where needed).
- Keep SwiftData and UI mutations on main actor.
- Bridge callback APIs into async APIs instead of pushing callbacks upward.
- Respect actor isolation; avoid nonisolated mutable shared state.

### Naming

- Types: `UpperCamelCase` (`SyncWithGoogleUseCase`).
- Functions/properties: `lowerCamelCase`.
- Test names use behavior-oriented snake style (e.g., `test_happyPath_insertsAndLogsAnalytics`).
- Prefer explicit domain names (`pendingOrFailedGlucoseSync`) over vague abbreviations.

### Error Handling and Logging

- Prefer typed errors for subsystems (`GoogleSheetsClientError`).
- Use `do/catch`; propagate errors unless intentionally degraded.
- For best-effort side effects, log and continue when appropriate.
- Use `OSLog` for production-facing logs; `print` is acceptable behind `#if DEBUG`.
- Convert technical errors to user-facing messages in view models when needed.

### SwiftUI Guidance

- Keep views declarative and lightweight; move business logic to use cases/view models.
- Reuse design tokens/helpers from `DDiary/UI/DesignSystem.swift`.
- Keep status/formatting logic centralized in helper types when practical.

### Testing Expectations

- Add/adjust tests for behavior changes.
- Prefer unit tests around use cases and repository behavior.
- Use mocks/test doubles from `DDiaryTests/TestSupport.swift` and related test helpers.
- For regression fixes, add a focused test that fails before and passes after.

### Security and Secrets

- Never commit secrets or tokens.
- `Configs/Secrets.xcconfig` is gitignored and must remain local/CI-generated.
- Avoid logging sensitive credentials (refresh tokens, API keys, etc.).

## Agent Workflow Expectations

- Keep changes scoped; avoid unrelated refactors.
- Preserve existing architecture boundaries (View -> ViewModel -> UseCase -> Repository).
- Do not add new dependencies/tools unless task requires it.
- Before finalizing, run targeted tests first, then broader suite if needed.
- If you cannot run tests locally, state exactly what was not run.

## Cursor / Copilot Rules Status

- `.cursor/rules/`: not present in tracked repository.
- `.cursorrules`: not present in tracked repository.
- `.github/copilot-instructions.md`: not present in tracked repository.
- If any of these files are added later, treat them as higher-priority agent instructions and update this file.

## Pre-PR Quick Checklist

- Build succeeds for touched targets.
- Relevant tests pass (or explicitly report what was skipped).
- No secrets or local config files added to git.
- Docs updated when behavior/configuration changed.
