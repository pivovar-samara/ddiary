import Foundation
import OSLog

@MainActor
public protocol SchedulesUpdating {
    func scheduleFromCurrentSettings() async throws
}

@MainActor
public final class UpdateSchedulesUseCase: SchedulesUpdating {
    private enum UserSurfacePolicy: String {
        case suppressed
    }

    private let settingsRepository: any SettingsRepository
    private let notificationsRepository: any NotificationsRepository
    private let analyticsRepository: any AnalyticsRepository
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "DDiary",
        category: "UpdateSchedulesUseCase"
    )
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
            log(error, operation: "requestAuthorizationAndSchedule", policy: .suppressed)
        }
    }

    /// Reschedules both BP and Glucose notifications using the current settings from the repository.
    /// Call this after saving settings.
    public func scheduleFromCurrentSettings() async throws {
        do {
            let settings = try await settingsRepository.getOrCreate()
            try await ensureCycleAnchorIfNeeded(settings: settings)
            try await notificationsRepository.scheduleAllNotifications(settings: settings)
            await analyticsRepository.logScheduleUpdated(kind: .bloodPressure)
            await analyticsRepository.logScheduleUpdated(kind: .glucose)
        } catch {
            let reason = String(describing: error)
            await analyticsRepository.logScheduleUpdateFailed(kind: .bloodPressure, reason: reason)
            await analyticsRepository.logScheduleUpdateFailed(kind: .glucose, reason: reason)
            throw error
        }
    }

    private func ensureCycleAnchorIfNeeded(settings: UserSettings) async throws {
        guard settings.enableDailyCycleMode else { return }
        guard settings.dailyCycleAnchorDate == nil else { return }
        settings.dailyCycleAnchorDate = GlucoseCyclePlanner.fallbackAnchorDate(
            currentCycleIndex: settings.currentCycleIndex
        )
        try await settingsRepository.save(settings)
    }

    private func log(_ error: Error, operation: String, policy: UserSurfacePolicy) {
        logger.error(
            "\(operation, privacy: .public) failed. user_surface=\(policy.rawValue, privacy: .public) error=\(String(describing: error), privacy: .public)"
        )
    }
}
