//
//  DDiaryApp.swift
//  DDiary
//
//  Created by Ilia Khokhlov on 24.11.25.
//

import SwiftUI
import SwiftData
import UserNotifications
import OSLog

private enum PersistenceConstants {
    static let cloudKitContainerIdentifier = "iCloud.container.diary"
}

enum AppLaunchNotice: Equatable {
    case cloudSyncUnavailable

    var title: String {
        switch self {
        case .cloudSyncUnavailable:
            L10n.cloudSyncUnavailableTitle
        }
    }

    var message: String {
        switch self {
        case .cloudSyncUnavailable:
            L10n.cloudSyncUnavailableMessage
        }
    }
}

enum AppLaunchState {
    case ready(sharedModelContainer: ModelContainer, appContainer: AppContainer, launchNotice: AppLaunchNotice?)
    case failed(message: String)
}

@MainActor
struct AppBootstrapper {
    typealias ModelContainerFactory = (_ schema: Schema, _ configurations: [ModelConfiguration]) throws -> ModelContainer
    typealias AppContainerFactory = (_ modelContainer: ModelContainer) -> AppContainer

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "DDiary",
        category: "AppBootstrapper"
    )

    static func makeLaunchState(
        isUITesting: Bool,
        usesPrettyData: Bool = false,
        appContainerFactory: AppContainerFactory = { modelContainer in
            AppContainer(modelContainer: modelContainer)
        },
        prettyDataAppContainerFactory: AppContainerFactory = { modelContainer in
            AppContainer.prettyData(modelContainer: modelContainer)
        },
        modelContainerFactory: ModelContainerFactory = { schema, configurations in
            try ModelContainer(for: schema, configurations: configurations)
        }
    ) -> AppLaunchState {
        let fullSchema = Schema([
            BPMeasurement.self,
            GlucoseMeasurement.self,
            UserSettings.self,
            GoogleIntegration.self,
        ])

        if isUITesting || usesPrettyData {
            do {
                return try makeReadyLaunchState(
                    fullSchema: fullSchema,
                    configuration: ModelConfiguration(
                        schema: fullSchema,
                        isStoredInMemoryOnly: true,
                        cloudKitDatabase: .none
                    ),
                    launchNotice: nil,
                    appContainerFactory: usesPrettyData ? prettyDataAppContainerFactory : appContainerFactory,
                    seedPrettyData: usesPrettyData,
                    modelContainerFactory: modelContainerFactory
                )
            } catch {
                let message = L10n.startupStorageInitFailed(error.localizedDescription)
                return .failed(message: message)
            }
        }

        do {
            return try makeReadyLaunchState(
                fullSchema: fullSchema,
                configuration: ModelConfiguration(
                    schema: fullSchema,
                    cloudKitDatabase: .private(PersistenceConstants.cloudKitContainerIdentifier)
                ),
                launchNotice: nil,
                appContainerFactory: appContainerFactory,
                modelContainerFactory: modelContainerFactory
            )
        } catch let cloudKitError {
            logger.error(
                "CloudKit-backed ModelContainer init failed. Falling back to local-only persistence. error=\(String(describing: cloudKitError), privacy: .public)"
            )

            do {
                return try makeReadyLaunchState(
                    fullSchema: fullSchema,
                    configuration: ModelConfiguration(
                        schema: fullSchema,
                        cloudKitDatabase: .none
                    ),
                    launchNotice: .cloudSyncUnavailable,
                    appContainerFactory: appContainerFactory,
                    modelContainerFactory: modelContainerFactory
                )
            } catch let localError {
                logger.fault(
                    "Local-only fallback ModelContainer init failed after CloudKit init failure. cloud_error=\(String(describing: cloudKitError), privacy: .public) local_error=\(String(describing: localError), privacy: .public)"
                )

                let message = L10n.startupStorageInitFailed(localError.localizedDescription)
                return .failed(message: message)
            }
        }
    }

    private static func makeReadyLaunchState(
        fullSchema: Schema,
        configuration: ModelConfiguration,
        launchNotice: AppLaunchNotice?,
        appContainerFactory: AppContainerFactory,
        seedPrettyData: Bool = false,
        modelContainerFactory: ModelContainerFactory
    ) throws -> AppLaunchState {
        let sharedModelContainer = try modelContainerFactory(fullSchema, [configuration])
        if seedPrettyData {
            try PrettyDataSeeder.seed(.showcase, into: sharedModelContainer)
        }
        let appContainer = appContainerFactory(sharedModelContainer)
        return .ready(
            sharedModelContainer: sharedModelContainer,
            appContainer: appContainer,
            launchNotice: launchNotice
        )
    }
}

@main
struct DDiaryApp: App {
    private let launchState: AppLaunchState
    private let notificationsCoordinator: NotificationsCoordinator?
    private let isUITesting: Bool
    private let usesPrettyData: Bool

    init() {
        let args = ProcessInfo.processInfo.arguments
        let env = ProcessInfo.processInfo.environment
        self.isUITesting = args.contains("UITESTING") || env["UITESTING"] == "1"
        self.usesPrettyData = args.contains("PRETTY_DATA") || env["PRETTY_DATA"] == "1"
        self.launchState = AppBootstrapper.makeLaunchState(
            isUITesting: isUITesting,
            usesPrettyData: usesPrettyData
        )

        switch launchState {
        case let .ready(_, appContainer, _):
            if usesPrettyData {
                self.notificationsCoordinator = nil
            } else {
                UserNotificationsRepository.registerCategories()
                let center = UNUserNotificationCenter.current()
                let coordinator = NotificationsCoordinator(container: appContainer)
                center.delegate = coordinator
                self.notificationsCoordinator = coordinator
            }
            Task { @MainActor in
                await appContainer.analyticsRepository.logAppOpen()
            }
        case .failed:
            self.notificationsCoordinator = nil
        }
    }

    var body: some Scene {
        WindowGroup {
            switch launchState {
            case let .ready(sharedModelContainer, appContainer, launchNotice):
                RootView(launchNotice: launchNotice)
                    .appContainer(appContainer)
                    .modelContainer(sharedModelContainer)
            case .failed(let message):
                StartupErrorView(message: message)
            }
        }
    }
}

private struct StartupErrorView: View {
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
            Text(L10n.startupTitle)
                .font(.title3)
                .fontWeight(.semibold)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text(L10n.startupRecoveryHint)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .accessibilityIdentifier("startup.error")
    }
}
