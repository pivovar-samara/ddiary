//
//  CloudSyncStatusMonitor.swift
//  DDiary
//

import CoreData
import Foundation
import Observation
import OSLog

/// A CloudKit mirroring event reduced to the `Sendable` facts the app acts on.
///
/// `NSPersistentCloudKitContainer.Event` is not `Sendable`, so it is flattened into this value
/// inside the notification callback instead of being carried across to the main actor.
nonisolated struct CloudSyncEvent: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case setup
        case dataImport
        case dataExport
        case unknown
    }

    let kind: Kind
    let hasEnded: Bool
    let succeeded: Bool
    let errorDescription: String?

    init(kind: Kind, hasEnded: Bool, succeeded: Bool, errorDescription: String? = nil) {
        self.kind = kind
        self.hasEnded = hasEnded
        self.succeeded = succeeded
        self.errorDescription = errorDescription
    }
}

/// Tracks whether CloudKit mirroring actually works for the app's store.
///
/// A missing iCloud account does not make `ModelContainer` init throw: SwiftData builds the store
/// and returns, and `NSPersistentCloudKitContainer` reports the failure only afterwards, through
/// `eventChangedNotification`. The startup fallback in `AppBootstrapper` therefore never sees it,
/// so without this monitor the app would silently run local-only while telling the user nothing.
@MainActor
@Observable
final class CloudSyncStatusMonitor {
    private(set) var isCloudSyncUnavailable = false

    @ObservationIgnored private let center: NotificationCenter
    @ObservationIgnored private var observer: NSObjectProtocol?

    @ObservationIgnored private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "DDiary",
        category: "CloudSyncStatusMonitor"
    )

    init(center: NotificationCenter = .default) {
        self.center = center
    }

    func startObserving() {
        guard observer == nil else { return }

        observer = center.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let event = Self.makeEvent(from: notification) else { return }
            Task { @MainActor [weak self] in
                self?.record(event)
            }
        }
    }

    func stopObserving() {
        guard let observer else { return }
        center.removeObserver(observer)
        self.observer = nil
    }

    /// Applies a mirroring event. Exposed so tests can drive the state machine without CoreData.
    func record(_ event: CloudSyncEvent) {
        guard event.hasEnded else { return }

        if event.succeeded {
            guard isCloudSyncUnavailable else { return }
            Self.logger.notice("CloudKit mirroring recovered; cloud sync is available again.")
            isCloudSyncUnavailable = false
            return
        }

        // Only a failed setup means mirroring never started. Import/export failures are routinely
        // transient (offline, throttling) and must not flip the app into "sync unavailable".
        guard event.kind == .setup, !isCloudSyncUnavailable else { return }

        Self.logger.error(
            "CloudKit mirroring setup failed. App runs local-only. error=\(event.errorDescription ?? "nil", privacy: .public)"
        )
        isCloudSyncUnavailable = true
    }

    nonisolated private static func makeEvent(from notification: Notification) -> CloudSyncEvent? {
        guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
            as? NSPersistentCloudKitContainer.Event else {
            return nil
        }

        let kind: CloudSyncEvent.Kind = switch event.type {
        case .setup: .setup
        case .import: .dataImport
        case .export: .dataExport
        @unknown default: .unknown
        }

        return CloudSyncEvent(
            kind: kind,
            hasEnded: event.endDate != nil,
            succeeded: event.succeeded,
            errorDescription: event.error.map { String(describing: $0) }
        )
    }
}
