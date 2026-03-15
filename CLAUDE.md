# CLAUDE.md

Claude Code guidance for the DDiary project. See [AGENTS.md](AGENTS.md) for full style guide and pre-PR checklist.

## Project at a Glance

iOS/iPadOS 26+ app · Swift 6 · SwiftUI + Observation · SwiftData + CloudKit · MVVM + UseCase + Repository + manual DI

Architecture layers (strict, top-down):
```
View → ViewModel (@MainActor @Observable) → UseCase (@MainActor) → Repository (protocol) → SwiftData Models
```

DI root: `DDiary/AppContainer.swift` — wire all new dependencies here.

## Simulator Destination

Always use this unless told otherwise:
```
DEST="platform=iOS Simulator,OS=26.2,name=iPhone 17 Pro"
```

## Build Commands

```bash
# Build app
xcodebuild build -project DDiary.xcodeproj -scheme DDiary -destination "$DEST"

# Build for testing (faster, no re-compile on test run)
xcodebuild build-for-testing -project DDiary.xcodeproj -scheme DDiary -destination "$DEST"
```

## Test Commands

```bash
# Full unit test suite
xcodebuild test -project DDiary.xcodeproj -scheme DDiaryTests -destination "$DEST" \
  -destination-timeout 180 -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1

# Minimal PR test plan (what CI runs)
xcodebuild test -project DDiary.xcodeproj -scheme DDiary -testPlan DDiaryMinimal \
  -destination "$DEST" -destination-timeout 180 -parallel-testing-enabled NO \
  -maximum-concurrent-test-simulator-destinations 1

# Single test class
xcodebuild test -project DDiary.xcodeproj -scheme DDiaryTests -destination "$DEST" \
  -only-testing:DDiaryTests/LogBPMeasurementUseCaseTests

# Single test method
xcodebuild test -project DDiary.xcodeproj -scheme DDiaryTests -destination "$DEST" \
  -only-testing:DDiaryTests/LogBPMeasurementUseCaseTests/test_happyPath_insertsAndLogsAnalytics
```

Parallel testing is disabled — the test suite uses in-memory SwiftData, which is not thread-safe across simulators.

## Key Non-Obvious Decisions

- **Google OAuth refresh token** is stored in the **Keychain** (`KeychainTokenStorage`), NOT in SwiftData/CloudKit. The `GoogleIntegration` model has no `refreshToken` field.
- **New Swift files auto-compile** — Xcode project uses `PBXFileSystemSynchronizedRootGroup`. Drop a `.swift` file into the right folder; no `project.pbxproj` edit needed.
- **CloudKit is not active during testing** — tests use in-memory SwiftData only.
- **Secrets** — `Configs/Secrets.xcconfig` is gitignored. Copy from `Secrets.xcconfig.example` and fill locally. Never commit it.

## Test Doubles (DDiaryTests/TestSupport.swift)

| Double | What it provides |
|---|---|
| `InMemoryTokenStorage` | In-memory `TokenStorage` — use instead of real Keychain in tests |
| `MockAnalyticsRepository` | Records all analytics calls for assertion |
| `RecordingGoogleSheetsClient` | Succeeds or fails on demand; records calls |
| `XCTAssertThrowsErrorAsync` | Helper for async-throws assertions |
| `MockKeychainInterface` | In `KeychainTokenStorageTests.swift`; mocks raw keychain ops |

## Repository Layer

- Protocols: `DDiary/Repository/RepositoryProtocols.swift`
- SwiftData implementations: `DDiary/Repository/SwiftData*.swift`
- Mock implementations: `DDiary/Repository/MockRepositories.swift`
- Token storage: `DDiary/Repository/KeychainTokenStorage.swift`

## Adding a New UseCase

1. Create `DDiary/UseCases/MyNewUseCase.swift` (auto-compiles)
2. Define as `@MainActor final class MyNewUseCase { ... }`
3. Add property + init parameter to `AppContainer`

## Test Naming Convention

```swift
func test_happyPath_insertsAndLogsAnalytics() { ... }
func test_whenRepositoryThrows_propagatesError() { ... }
```
