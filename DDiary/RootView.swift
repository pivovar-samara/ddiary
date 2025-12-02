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
        Text("DDiary — Coming soon…")
            .font(.title2)
            .padding()
            .navigationTitle("DDiary")
    }
}

#Preview {
    NavigationStack {
        RootView()
    }
    .appContainer(.preview)
}
