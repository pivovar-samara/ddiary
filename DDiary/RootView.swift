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
                    TodayView().navigationTitle("Today")
                }
                .tabItem {
                    Label("Today", systemImage: "calendar")
                }
                
                // History
                NavigationStack {
                    HistoryView().navigationTitle("History")
                }
                .tabItem {
                    Label("History", systemImage: "clock")
                }
                
                // Settings
                NavigationStack {
                    SettingsView().navigationTitle("Settings")
                }
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
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
