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

@main
struct DDiaryApp: App {
    let sharedModelContainer: ModelContainer
    let appContainer: AppContainer
    private let notificationsCoordinator: NotificationsCoordinator
    private let isUITesting: Bool

    init() {
        let args = ProcessInfo.processInfo.arguments
        let env = ProcessInfo.processInfo.environment
        self.isUITesting = args.contains("UITESTING") || env["UITESTING"] == "1"

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
            let container = try ModelContainer(for: fullSchema, configurations: [modelConfiguration])
            self.sharedModelContainer = container
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }

        // Wire up dependencies via a single AppContainer instance.
        self.appContainer = AppContainer(modelContainer: sharedModelContainer)
        
        // Configure notification categories and delegate
        UserNotificationsRepository.registerCategories()
        let center = UNUserNotificationCenter.current()
        let coordinator = NotificationsCoordinator(container: self.appContainer)
        center.delegate = coordinator
        self.notificationsCoordinator = coordinator
    }
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .appContainer(appContainer)
        }
        .modelContainer(sharedModelContainer)
    }
}
