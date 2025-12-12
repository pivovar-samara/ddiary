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
                // Menu
                NavigationStack {
                    TodayView().navigationTitle("Today")
                }
                .tabItem {
                    Label("Today", systemImage: "calendar")
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
