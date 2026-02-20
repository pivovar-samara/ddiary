//
//  DDiaryApp.swift
//  DDiary
//
//  Created by Ilia Khokhlov on 24.11.25.
//

import SwiftUI
import SwiftData
import UserNotifications

private enum PersistenceConstants {
    static let cloudKitContainerIdentifier = "iCloud.container.diary"
}

enum AppLaunchState {
    case ready(sharedModelContainer: ModelContainer, appContainer: AppContainer)
    case failed(message: String)
}

@MainActor
struct AppBootstrapper {
    typealias ModelContainerFactory = (_ schema: Schema, _ configurations: [ModelConfiguration]) throws -> ModelContainer

    static func makeLaunchState(
        isUITesting: Bool,
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

        let modelConfiguration: ModelConfiguration
        if isUITesting {
            modelConfiguration = ModelConfiguration(
                schema: fullSchema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        } else {
            modelConfiguration = ModelConfiguration(
                schema: fullSchema,
                cloudKitDatabase: .private(PersistenceConstants.cloudKitContainerIdentifier)
            )
        }

        do {
            let sharedModelContainer = try modelContainerFactory(fullSchema, [modelConfiguration])
            let appContainer = AppContainer(modelContainer: sharedModelContainer)
            return .ready(sharedModelContainer: sharedModelContainer, appContainer: appContainer)
        } catch {
            let message = L10n.startupStorageInitFailed(error.localizedDescription)
            return .failed(message: message)
        }
    }
}

@main
struct DDiaryApp: App {
    private let launchState: AppLaunchState
    private let notificationsCoordinator: NotificationsCoordinator?
    private let isUITesting: Bool

    init() {
        let args = ProcessInfo.processInfo.arguments
        let env = ProcessInfo.processInfo.environment
        self.isUITesting = args.contains("UITESTING") || env["UITESTING"] == "1"
        self.launchState = AppBootstrapper.makeLaunchState(isUITesting: isUITesting)

        switch launchState {
        case .ready(_, let appContainer):
            // Configure notification categories and delegate
            UserNotificationsRepository.registerCategories()
            let center = UNUserNotificationCenter.current()
            let coordinator = NotificationsCoordinator(container: appContainer)
            center.delegate = coordinator
            self.notificationsCoordinator = coordinator
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
            case .ready(let sharedModelContainer, let appContainer):
                RootView()
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
