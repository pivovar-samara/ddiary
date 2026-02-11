import Foundation

@MainActor
public protocol SchedulesUpdating {
    func scheduleFromCurrentSettings() async throws
}

@MainActor
public final class UpdateSchedulesUseCase: SchedulesUpdating {
    private let settingsRepository: any SettingsRepository
    private let notificationsRepository: any NotificationsRepository
    private let analyticsRepository: any AnalyticsRepository
    private var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("UITESTING")
        || ProcessInfo.processInfo.environment["UITESTING"] == "1"
    }

    public init(
        settingsRepository: any SettingsRepository,
        notificationsRepository: any NotificationsRepository,
        analyticsRepository: any AnalyticsRepository
    ) {
        self.settingsRepository = settingsRepository
        self.notificationsRepository = notificationsRepository
        self.analyticsRepository = analyticsRepository
    }

    /// Request authorization (if needed) and schedule all notifications from the current settings.
    /// Call this on app launch after setting up categories and a delegate.
    public func requestAuthorizationAndSchedule() async {
        guard !isUITesting else { return }
        do {
            let granted = try await notificationsRepository.requestAuthorization()
            guard granted else { return }
            let settings = try await settingsRepository.getOrCreate()
            try await notificationsRepository.scheduleAllNotifications(settings: settings)
        } catch {
            // For v1, fail silently. Consider logging in later releases.
        }
    }

    /// Reschedules both BP and Glucose notifications using the current settings from the repository.
    /// Call this after saving settings.
    public func scheduleFromCurrentSettings() async throws {
        let settings = try await settingsRepository.getOrCreate()
        try await notificationsRepository.scheduleAllNotifications(settings: settings)
        await analyticsRepository.logScheduleUpdated(kind: .bloodPressure)
        await analyticsRepository.logScheduleUpdated(kind: .glucose)
    }
}
