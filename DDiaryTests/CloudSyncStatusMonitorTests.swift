import XCTest
@testable import DDiary

/// Every test here is `async` on purpose. The app target builds with
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so its `@MainActor` classes get an isolated
/// deinit; releasing one from a *synchronous* test aborts the whole test process on the iOS 26.x
/// runtime (`pointer being freed was not allocated`). Running on an async test keeps the release
/// on the main actor's executor, which is the path the runtime handles correctly.
@MainActor
final class CloudSyncStatusMonitorTests: XCTestCase {

    func test_initialState_reportsCloudSyncAvailable() async {
        let monitor = CloudSyncStatusMonitor(center: NotificationCenter())

        XCTAssertFalse(monitor.isCloudSyncUnavailable)
    }

    func test_whenSetupFails_reportsCloudSyncUnavailable() async {
        let monitor = CloudSyncStatusMonitor(center: NotificationCenter())

        monitor.record(
            CloudSyncEvent(
                kind: .setup,
                hasEnded: true,
                succeeded: false,
                errorDescription: "CKAccountStatusNoAccount"
            )
        )

        XCTAssertTrue(monitor.isCloudSyncUnavailable)
    }

    func test_whenSetupSucceeds_keepsCloudSyncAvailable() async {
        let monitor = CloudSyncStatusMonitor(center: NotificationCenter())

        monitor.record(CloudSyncEvent(kind: .setup, hasEnded: true, succeeded: true))

        XCTAssertFalse(monitor.isCloudSyncUnavailable)
    }

    func test_whenSetupIsStillRunning_ignoresEvent() async {
        let monitor = CloudSyncStatusMonitor(center: NotificationCenter())

        monitor.record(CloudSyncEvent(kind: .setup, hasEnded: false, succeeded: false))

        XCTAssertFalse(monitor.isCloudSyncUnavailable)
    }

    func test_whenImportOrExportFails_keepsCloudSyncAvailable() async {
        let monitor = CloudSyncStatusMonitor(center: NotificationCenter())

        monitor.record(CloudSyncEvent(kind: .dataImport, hasEnded: true, succeeded: false))
        monitor.record(CloudSyncEvent(kind: .dataExport, hasEnded: true, succeeded: false))

        XCTAssertFalse(monitor.isCloudSyncUnavailable)
    }

    func test_whenSetupFailsThenLaterEventSucceeds_reportsCloudSyncAvailableAgain() async {
        let monitor = CloudSyncStatusMonitor(center: NotificationCenter())

        monitor.record(CloudSyncEvent(kind: .setup, hasEnded: true, succeeded: false))
        XCTAssertTrue(monitor.isCloudSyncUnavailable)

        monitor.record(CloudSyncEvent(kind: .dataImport, hasEnded: true, succeeded: true))

        XCTAssertFalse(monitor.isCloudSyncUnavailable)
    }

    func test_whenSetupFailsAfterRecovery_reportsCloudSyncUnavailableAgain() async {
        let monitor = CloudSyncStatusMonitor(center: NotificationCenter())

        monitor.record(CloudSyncEvent(kind: .setup, hasEnded: true, succeeded: false))
        monitor.record(CloudSyncEvent(kind: .setup, hasEnded: true, succeeded: true))
        XCTAssertFalse(monitor.isCloudSyncUnavailable)

        // Signing back out of iCloud fails setup a second time within the same session.
        monitor.record(CloudSyncEvent(kind: .setup, hasEnded: true, succeeded: false))

        XCTAssertTrue(monitor.isCloudSyncUnavailable)
    }

    func test_startObserving_isIdempotent_andSurvivesStopAndRestart() async {
        let center = NotificationCenter()
        let monitor = CloudSyncStatusMonitor(center: center)

        monitor.startObserving()
        monitor.startObserving()
        monitor.stopObserving()
        monitor.stopObserving()
        monitor.startObserving()

        XCTAssertFalse(monitor.isCloudSyncUnavailable)
    }

    // MARK: - Startup fallback

    func test_markUnavailable_flipsTheFlag() async {
        let monitor = CloudSyncStatusMonitor(center: NotificationCenter())
        monitor.markUnavailable()
        XCTAssertTrue(monitor.isCloudSyncUnavailable)
    }

    /// The startup fallback and a later mirroring recovery have to agree on one flag, otherwise
    /// the UI would keep showing "unavailable" after the user signs back into iCloud.
    func test_markUnavailable_thenSuccessfulSetup_clearsTheFlag() async {
        let monitor = CloudSyncStatusMonitor(center: NotificationCenter())
        monitor.markUnavailable()
        monitor.record(CloudSyncEvent(kind: .setup, hasEnded: true, succeeded: true))
        XCTAssertFalse(monitor.isCloudSyncUnavailable)
    }
}
