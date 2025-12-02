//
//  DDiaryApp.swift
//  DDiary
//
//  Created by Ilia Khokhlov on 24.11.25.
//

import SwiftUI
import SwiftData

@main
struct DDiaryApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            BPMeasurement.self,
            GlucoseMeasurement.self,
            UserSettings.self,
            GoogleIntegration.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    var body: some Scene {
        WindowGroup {
            let container = AppContainer(modelContainer: sharedModelContainer)
            RootView()
                .appContainer(container)
        }
        .modelContainer(sharedModelContainer)
    }
}
