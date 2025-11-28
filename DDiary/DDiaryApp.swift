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
    private let sharedModelContainer: ModelContainer
    private let appContainer: AppContainer

    init() {
        let schema = Schema([
            BPMeasurementModel.self,
            GlucoseMeasurementModel.self,
            GlucoseRotationConfigModel.self,
            UserSettings.self,
            GoogleIntegration.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            let modelContext = ModelContext(container)
            self.sharedModelContainer = container
            self.appContainer = AppContainer(
                modelContainer: container,
                measurementsRepository: SwiftDataMeasurementsRepository(modelContext: modelContext),
                rotationScheduleRepository: SwiftDataRotationScheduleRepository(modelContext: modelContext),
                settingsRepository: SwiftDataSettingsRepository(modelContext: modelContext)
            )
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .appContainer(appContainer)
        }
        .modelContainer(sharedModelContainer)
    }
}
