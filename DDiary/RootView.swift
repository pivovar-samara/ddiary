//
//  RootView.swift
//  DDiary
//
//  Created by Ilia Khokhlov on 24.11.25.
//

import SwiftUI

struct RootView: View {
    @Environment(\.appContainer) private var container: AppContainer

    var body: some View {
        ZStack(alignment: .top) {
            TabView {
                // Today
                NavigationStack {
                    TodayView().navigationTitle(L10n.screenTodayTitle)
                }
                .tabItem {
                    Label(L10n.tabToday, systemImage: "calendar")
                }
                
                // History
                NavigationStack {
                    HistoryView().navigationTitle(L10n.screenHistoryTitle)
                }
                .tabItem {
                    Label(L10n.tabHistory, systemImage: "clock")
                }
                
                // Settings
                NavigationStack {
                    SettingsView().navigationTitle(L10n.screenSettingsTitle)
                }
                .tabItem {
                    Label(L10n.tabSettings, systemImage: "gear")
                }
            }
            .task {
                await container.updateSchedulesUseCase.requestAuthorizationAndSchedule()
            }
        }
    }
}

#Preview {
    NavigationStack {
        RootView()
    }
    .appContainer(.preview)
}
