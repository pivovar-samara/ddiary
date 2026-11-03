import Foundation

/// Current time for the Today screen and the demo seeder.
///
/// In a `PRETTY_DATA` launch, a `DEMO_TIME=HH:MM` argument (or environment variable) pins the
/// clock to that time of the current day, so App Store screenshots look the same whenever they
/// are taken. Every other launch uses the real time.
nonisolated enum AppClock {
    static var now: Date {
        guard let pinned = pinnedTime else { return Date() }
        let calendar = Calendar.current
        return calendar.date(
            bySettingHour: pinned.hour,
            minute: pinned.minute,
            second: 0,
            of: Date()
        ) ?? Date()
    }

    private static let pinnedTime: (hour: Int, minute: Int)? = {
        let process = ProcessInfo.processInfo
        guard AnalyticsEnvironment.current().isPrettyData else { return nil }
        let raw = process.arguments
            .first { $0.hasPrefix("DEMO_TIME=") }
            .map { String($0.dropFirst("DEMO_TIME=".count)) }
            ?? process.environment["DEMO_TIME"]
        let parts = raw?.split(separator: ":").compactMap { Int($0) } ?? []
        guard parts.count == 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) else {
            return nil
        }
        return (parts[0], parts[1])
    }()
}
