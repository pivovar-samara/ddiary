//
//  AnalyticsEvent.swift
//  DDiary
//

import Foundation

/// Closed set of value types an analytics property may carry.
///
/// A closed enum rather than `Any` keeps `AnalyticsEvent` both `Sendable` and `Equatable`,
/// which is what makes the event mapping assertable in tests.
public nonisolated enum AnalyticsValue: Sendable, Equatable {
    case string(String)
    case int(Int)

    var objectValue: Any {
        switch self {
        case let .string(value):
            return value
        case let .int(value):
            return value
        }
    }
}

/// Provider-agnostic description of one analytics event.
public nonisolated struct AnalyticsEvent: Sendable, Equatable {
    public let name: String
    public let properties: [String: AnalyticsValue]

    public init(name: String, properties: [String: AnalyticsValue] = [:]) {
        self.name = name
        self.properties = properties
    }

    /// Bridge to the `[String: Any]?` shape both vendor SDKs accept.
    ///
    /// Returns `nil` rather than `[:]` when there are no properties, preserving the exact
    /// payloads the app has always sent for property-less events.
    public var objectProperties: [String: Any]? {
        properties.isEmpty ? nil : properties.mapValues(\.objectValue)
    }
}
