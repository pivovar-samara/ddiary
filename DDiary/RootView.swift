//
//  RootView.swift
//  DDiary
//
//  Created by Ilia Khokhlov on 24.11.25.
//

import SwiftUI
import Combine

private enum RootTab: Hashable {
    case today
    case history
    case settings
#if DEBUG
    case debug
#endif
}

struct RootView: View {
    let launchNotice: AppLaunchNotice?

    @Environment(\.appContainer) private var container: AppContainer
    @State private var selectedTab: RootTab = .today
    @State private var activeLaunchNotice: AppLaunchNotice?
    @State private var hasPresentedCloudSyncNotice: Bool

    init(launchNotice: AppLaunchNotice? = nil) {
        self.launchNotice = launchNotice
        _activeLaunchNotice = State(initialValue: launchNotice)
        // A notice raised at launch already covers the cloud-sync case; don't repeat it when the
        // mirroring failure lands afterwards.
        _hasPresentedCloudSyncNotice = State(initialValue: launchNotice == .cloudSyncUnavailable)
    }

    var body: some View {
        ZStack(alignment: .top) {
            TabView(selection: $selectedTab) {
                // Today
                NavigationStack {
                    TodayView(isActiveTab: selectedTab == .today)
                        .navigationTitle(L10n.screenTodayTitle)
                }
                .tag(RootTab.today)
                .tabItem {
                    Label(L10n.tabToday, systemImage: "calendar")
                }
                
                // History
                NavigationStack {
                    HistoryView().navigationTitle(L10n.screenHistoryTitle)
                }
                .tag(RootTab.history)
                .tabItem {
                    Label(L10n.tabHistory, systemImage: "clock")
                }
                
                // Settings
                NavigationStack {
                    SettingsView().navigationTitle(L10n.screenSettingsTitle)
                }
                .tag(RootTab.settings)
                .tabItem {
                    Label(L10n.tabSettings, systemImage: "gear")
                }

#if DEBUG
                if !container.isPrettyDataMode {
                NavigationStack {
                    DebugView().navigationTitle(L10n.screenDebugTitle)
                }
                .tag(RootTab.debug)
                .tabItem {
                    Label(L10n.tabDebug, systemImage: "ladybug")
                }
                }
#endif
            }
            .onAppear {
                routeToTodayIfPendingQuickEntry()
            }
            .onReceive(NotificationCenter.default.publisher(for: .notificationQuickEntryRequested)) { _ in
                routeToTodayIfPendingQuickEntry()
            }
            .task {
                await container.updateSchedulesUseCase.requestAuthorizationAndSchedule()
            }
            // The mirroring failure can land either before this view appears or well after it.
            .task {
                presentCloudSyncNoticeIfNeeded()
            }
            .onChange(of: container.cloudSyncStatusMonitor.isCloudSyncUnavailable) { _, _ in
                presentCloudSyncNoticeIfNeeded()
            }
        }
        .alert(
            activeLaunchNotice?.title ?? "",
            isPresented: Binding(
                get: { activeLaunchNotice != nil },
                set: { isPresented in
                    if !isPresented {
                        activeLaunchNotice = nil
                    }
                }
            ),
            presenting: activeLaunchNotice
        ) { _ in
            Button(L10n.quickEntryAlertOK, role: .cancel) {}
        } message: { notice in
            Text(notice.message)
        }
    }

    private func presentCloudSyncNoticeIfNeeded() {
        guard container.cloudSyncStatusMonitor.isCloudSyncUnavailable else { return }
        guard !hasPresentedCloudSyncNotice else { return }
        hasPresentedCloudSyncNotice = true
        activeLaunchNotice = .cloudSyncUnavailable
    }

    private func routeToTodayIfPendingQuickEntry() {
        guard NotificationQuickEntryRouter.shared.hasPendingRequest else { return }
        selectedTab = .today
    }
}

#Preview {
    NavigationStack {
        RootView()
    }
    .appContainer(.preview)
}
