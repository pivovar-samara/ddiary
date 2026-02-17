import SwiftUI
import Observation

#if DEBUG
@MainActor
@Observable
final class DebugViewModel {
    private let notificationsRepository: any NotificationsRepository

    var isSchedulingBP: Bool = false
    var isSchedulingGlucose: Bool = false
    var statusMessage: String?
    var errorMessage: String?
    var isBusy: Bool { isSchedulingBP || isSchedulingGlucose }

    init(notificationsRepository: any NotificationsRepository) {
        self.notificationsRepository = notificationsRepository
    }

    func scheduleBPNotificationIn10Seconds() async {
        isSchedulingBP = true
        defer { isSchedulingBP = false }
        await schedule(kind: .bp)
    }

    func scheduleGlucoseNotificationIn10Seconds() async {
        isSchedulingGlucose = true
        defer { isSchedulingGlucose = false }
        await schedule(kind: .glucose)
    }

    private func schedule(kind: NotificationKind) async {
        do {
            let granted = try await notificationsRepository.requestAuthorization()
            guard granted else {
                statusMessage = nil
                errorMessage = L10n.debugAuthorizationDenied
                return
            }
            switch kind {
            case .bp:
                await notificationsRepository.scheduleDebugBloodPressureNotification(after: 10)
                statusMessage = L10n.debugScheduledBP
            case .glucose:
                await notificationsRepository.scheduleDebugGlucoseNotification(after: 10)
                statusMessage = L10n.debugScheduledGlucose
            }
            errorMessage = nil
        } catch {
            statusMessage = nil
            errorMessage = L10n.debugScheduleFailed(error.localizedDescription)
        }
    }

    private enum NotificationKind {
        case bp
        case glucose
    }
}

struct DebugView: View {
    @Environment(\.appContainer) private var container
    @State private var viewModel: DebugViewModel? = nil

    var body: some View {
        Group {
            if let vm = viewModel {
                content(for: vm)
            } else {
                ProgressView()
                    .task { await initializeViewModelIfNeeded() }
            }
        }
        .navigationTitle(L10n.screenDebugTitle)
    }

    @ViewBuilder
    private func content(for vm: DebugViewModel) -> some View {
        @Bindable var bvm = vm

        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.large) {
                Text(L10n.debugNotificationsHint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button {
                    Task { await vm.scheduleBPNotificationIn10Seconds() }
                } label: {
                    Label(L10n.debugGenerateBPNotification, systemImage: "heart.text.square")
                }
                .buttonStyle(.borderedProminent)
                .disabled(bvm.isBusy)
                .accessibilityIdentifier("debug.notifications.bp")

                Button {
                    Task { await vm.scheduleGlucoseNotificationIn10Seconds() }
                } label: {
                    Label(L10n.debugGenerateGlucoseNotification, systemImage: "drop")
                }
                .buttonStyle(.borderedProminent)
                .disabled(bvm.isBusy)
                .accessibilityIdentifier("debug.notifications.glucose")

                if let statusMessage = bvm.statusMessage {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage = bvm.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Spacer(minLength: 0)
            }
            .padding()
        }
    }

    @MainActor
    private func initializeViewModelIfNeeded() async {
        guard viewModel == nil else { return }
        viewModel = DebugViewModel(notificationsRepository: container.notificationsRepository)
    }
}

#Preview {
    NavigationStack {
        DebugView()
            .appContainer(.preview)
    }
}
#endif
