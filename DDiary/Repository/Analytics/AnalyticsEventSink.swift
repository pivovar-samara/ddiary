//
//  AnalyticsEventSink.swift
//  DDiary
//

import Foundation

/// One analytics provider. Fire-and-forget: sinks must never throw or block.
public nonisolated protocol AnalyticsEventSink: Sendable {
    func send(_ event: AnalyticsEvent)
}

/// Drops every event. Used when a provider is unavailable or telemetry is disabled.
public nonisolated struct NoopAnalyticsEventSink: AnalyticsEventSink {
    public init() {}

    public func send(_ event: AnalyticsEvent) {}
}
