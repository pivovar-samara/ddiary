//
//  UserNotificationsRepository.swift
//  DDiary
//
//  Created by Assistant on 26.11.25.
//

import Foundation
import UserNotifications

/// Concrete implementation of `NotificationsRepository` that wraps `UNUserNotificationCenter`.
///
/// NOTE: This is a stubbed implementation that models the API and basic flows.
/// Actual scheduling, identifiers, categories, and content need to be filled in (see TODOs).
public final class UserNotificationsRepository: NotificationsRepository {
    private let center: UNUserNotificationCenter

    public init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    // MARK: Authorization
    public func requestAuthorization() async throws -> Bool {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    // MARK: Scheduling - Blood Pressure
    public func scheduleBloodPressureNotifications(at times: [DateComponents], replaceExisting: Bool) async throws {
        if replaceExisting {
            try await cancelBloodPressureNotifications()
        }
        
        for time in times {
            let content = UNMutableNotificationContent()
            content.title = "Blood Pressure Reminder"
            content.body = "Please measure your blood pressure now."
            content.sound = .default
            
            let trigger = UNCalendarNotificationTrigger(dateMatching: time, repeats: true)
            let identifier = bpIdentifier(for: time)
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                center.add(request) { error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        }
    }

    // MARK: Scheduling - Glucose
    public func scheduleGlucoseNotifications(_ schedule: [GlucoseSlot: [DateComponents]], replaceExisting: Bool) async throws {
        if replaceExisting {
            try await cancelGlucoseNotifications(slots: nil)
        }
        
        for (slot, times) in schedule {
            for time in times {
                let content = UNMutableNotificationContent()
                content.title = "Glucose Reminder"
                content.body = "Please check your glucose level for \(slot.rawValue)."
                content.sound = .default
                
                let trigger = UNCalendarNotificationTrigger(dateMatching: time, repeats: true)
                let identifier = glucoseIdentifier(for: slot, time: time)
                let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
                
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    center.add(request) { error in
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume()
                        }
                    }
                }
            }
        }
    }

    // MARK: Cancel / Reschedule
    public func cancelAllScheduledNotifications() async throws {
        // NOTE: This removes all pending requests from this app.
        center.removeAllPendingNotificationRequests()
    }

    public func cancelBloodPressureNotifications() async throws {
        let pending = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[UNNotificationRequest], Error>) in
            center.getPendingNotificationRequests { requests in
                continuation.resume(returning: requests)
            }
        }
        let bpIdentifiers = pending.filter { $0.identifier.hasPrefix("bp-") }.map { $0.identifier }
        center.removePendingNotificationRequests(withIdentifiers: bpIdentifiers)
    }

    public func cancelGlucoseNotifications(slots: Set<GlucoseSlot>?) async throws {
        let pending = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[UNNotificationRequest], Error>) in
            center.getPendingNotificationRequests { requests in
                continuation.resume(returning: requests)
            }
        }
        let filteredIdentifiers: [String]
        if let slots = slots {
            filteredIdentifiers = pending.filter { request in
                guard request.identifier.hasPrefix("glucose-") else { return false }
                // Extract slot part from identifier: "glucose-\(slot.rawValue)-HH-MM"
                let components = request.identifier.split(separator: "-")
                guard components.count >= 3 else { return false }
                let slotPart = String(components[1])
                return slots.contains { $0.rawValue == slotPart }
            }.map { $0.identifier }
        } else {
            filteredIdentifiers = pending.filter { $0.identifier.hasPrefix("glucose-") }.map { $0.identifier }
        }
        center.removePendingNotificationRequests(withIdentifiers: filteredIdentifiers)
    }

    public func rescheduleBloodPressureNotifications(at times: [DateComponents]) async throws {
        // Example reschedule flow (stubbed):
        try await cancelBloodPressureNotifications()
        try await scheduleBloodPressureNotifications(at: times, replaceExisting: true)
    }

    public func rescheduleGlucoseNotifications(_ schedule: [GlucoseSlot: [DateComponents]]) async throws {
        // Example reschedule flow (stubbed):
        try await cancelGlucoseNotifications(slots: nil)
        try await scheduleGlucoseNotifications(schedule, replaceExisting: true)
    }

    // MARK: User Actions
    public func snoozeNotification(with identifier: String, by minutes: Int) async throws {
        // Fetch pending request
        let pendingRequests = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[UNNotificationRequest], Error>) in
            center.getPendingNotificationRequests { requests in
                continuation.resume(returning: requests)
            }
        }
        guard let request = pendingRequests.first(where: { $0.identifier == identifier }) else {
            return // No pending request found
        }
        guard let trigger = request.trigger as? UNCalendarNotificationTrigger, let nextDate = trigger.nextTriggerDate() else {
            return // Can't handle non-calendar triggers or missing next trigger date
        }
        let snoozedDate = Calendar.current.date(byAdding: .minute, value: minutes, to: nextDate)!
        let snoozeComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: snoozedDate)
        
        let newContent = request.content.mutableCopy() as! UNMutableNotificationContent
        // Optionally update content for snooze
        
        let newTrigger = UNCalendarNotificationTrigger(dateMatching: snoozeComponents, repeats: false)
        let newRequest = UNNotificationRequest(identifier: identifier, content: newContent, trigger: newTrigger)
        
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            center.add(newRequest) { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    public func skipNotification(with identifier: String) async throws {
        // TODO: Consider persisting a "skipped" state if you model it explicitly.
        // For now, just remove the pending request (if any).
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    public func moveNotification(with identifier: String, to date: Date) async throws {
        // Fetch pending request
        let pendingRequests = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[UNNotificationRequest], Error>) in
            center.getPendingNotificationRequests { requests in
                continuation.resume(returning: requests)
            }
        }
        guard let request = pendingRequests.first(where: { $0.identifier == identifier }) else {
            return // No pending request found
        }
        
        let dateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let newContent = request.content.mutableCopy() as! UNMutableNotificationContent
        let newTrigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        let newRequest = UNNotificationRequest(identifier: identifier, content: newContent, trigger: newTrigger)
        
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            center.add(newRequest) { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Identifier helpers (example scheme)
    private func bpIdentifier(for time: DateComponents) -> String {
        let h = time.hour ?? 0
        let m = time.minute ?? 0
        return String(format: "bp-%02d-%02d", h, m)
    }

    private func glucoseIdentifier(for slot: GlucoseSlot, time: DateComponents) -> String {
        let h = time.hour ?? 0
        let m = time.minute ?? 0
        return String(format: "glucose-%@-%02d-%02d", slot.rawValue, h, m)
    }
}
