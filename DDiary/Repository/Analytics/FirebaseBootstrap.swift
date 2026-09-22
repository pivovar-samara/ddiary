//
//  FirebaseBootstrap.swift
//  DDiary
//

import Foundation
import OSLog
import FirebaseCore
import FirebaseAnalytics
import FirebaseCrashlytics

/// Starts Firebase exactly once, and only in a real user session.
///
/// Collection itself is declared in Info.plist (`FIREBASE_ANALYTICS_COLLECTION_ENABLED`,
/// `FirebaseCrashlyticsCollectionEnabled`). We deliberately do **not** call
/// `setAnalyticsCollectionEnabled(_:)` or `setCrashlyticsCollectionEnabled(_:)`: both write a
/// sticky value to disk that outranks the plist on that install forever, which would leave the
/// plist an unreliable source of truth. The gate for test runs is simply never calling
/// `FirebaseApp.configure()` — without it the SDK never starts.
@MainActor
enum FirebaseBootstrap {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "DDiary",
        category: "FirebaseBootstrap"
    )

    private(set) static var isConfigured = false

    static func configureIfNeeded(environment: AnalyticsEnvironment) {
        guard !isConfigured else { return }

        guard environment.collectionEnabled else {
            logger.info("Firebase skipped: non-collecting launch (uitest/prettydata/unittest)")
            return
        }

        // The repository is public and GoogleService-Info.plist is gitignored, so a contributor
        // build legitimately has no Firebase config. Degrade to "no Firebase", never crash.
        guard Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil else {
            logger.error("Firebase disabled: GoogleService-Info.plist missing from bundle")
            return
        }

        FirebaseApp.configure()

        // Consent must be stated before any event is logged. Analytics storage only:
        // nothing about this app is advertising-related.
        Analytics.setConsent([
            .analyticsStorage: .granted,
            .adStorage: .denied,
            .adUserData: .denied,
            .adPersonalization: .denied,
        ])

        // Intentionally never calling Crashlytics.setUserID(_:) or setCustomValue(_:forKey:) —
        // crash reports carry only the random Firebase installation ID.
        // Reading the flag also keeps the Crashlytics component referenced so the linker
        // cannot drop it, and confirms in the log which way the plist resolved.
        let crashlyticsEnabled = Crashlytics.crashlytics().isCrashlyticsCollectionEnabled()
        logger.info("Firebase configured. crashlytics_collection=\(crashlyticsEnabled, privacy: .public)")

        isConfigured = true
    }
}
