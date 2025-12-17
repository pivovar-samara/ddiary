//
//  DDiaryApp.swift
//  DDiary
//
//  Created by Ilia Khokhlov on 24.11.25.
//

import SwiftUI
import SwiftData
import UserNotifications

@main
struct DDiaryApp: App {
    let sharedModelContainer: ModelContainer
    let appContainer: AppContainer
    private let notificationsCoordinator: NotificationsCoordinator

    init() {
        let schema = Schema([
            BPMeasurement.self,
            GlucoseMeasurement.self,
            UserSettings.self,
            GoogleIntegration.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
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
