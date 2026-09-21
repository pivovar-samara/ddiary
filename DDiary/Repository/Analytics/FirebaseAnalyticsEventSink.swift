//
//  FirebaseAnalyticsEventSink.swift
//  DDiary
//

import Foundation
import FirebaseCore
import FirebaseAnalytics

/// Firebase (Google Analytics 4) provider.
///
/// The only file in the analytics layer that imports a Firebase module, which is what keeps
/// the event mapping testable without linking the SDK into the test targets.
public nonisolated final class FirebaseAnalyticsEventSink: AnalyticsEventSink, @unchecked Sendable {
    public init() {}

    public func send(_ event: AnalyticsEvent) {
        guard FirebaseApp.app() != nil else { return }
        Analytics.logEvent(event.name, parameters: event.objectProperties)
    }
}
