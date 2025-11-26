//
//  ContentView.swift
//  DDiary
//
//  Created by Ilia Khokhlov on 24.11.25.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.appContainer) private var appContainer

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("DDiary")
                    .font(.largeTitle).bold()

                if appContainer == nil {
                    Text("AppContainer not injected")
                        .foregroundStyle(.red)
                } else {
                    Text("AppContainer injected")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
            .navigationTitle("Home")
        }
    }
}

#Preview {
    ContentView()
        .injectPlaceholderAppContainer()
}
