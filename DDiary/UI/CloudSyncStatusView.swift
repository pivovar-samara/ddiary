//
//  CloudSyncStatusView.swift
//  DDiary
//

import SwiftUI

/// Shared presentation of CloudKit mirroring state, so Today and Settings never disagree.
enum CloudSyncStatusPresentation {
    static func label(isUnavailable: Bool) -> String {
        isUnavailable ? L10n.settingsICloudStatusUnavailable : L10n.settingsICloudStatusActive
    }

    static func color(isUnavailable: Bool) -> Color {
        isUnavailable ? .orange : .green
    }
}

/// Inline notice shown on Today while iCloud sync is unavailable.
///
/// This used to be a modal alert. A missing or signed-out iCloud account raises the condition on
/// every single launch, and a dialog that reappears every launch gets dismissed unread — which is
/// the opposite of what a data-safety warning needs to achieve. Inline, it stays visible for as
/// long as the problem lasts and disappears by itself once mirroring recovers.
struct CloudSyncUnavailableNotice: View {
    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.small) {
            Image(systemName: "exclamationmark.icloud")
                .font(.body)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: DS.Spacing.xSmall) {
                Text(L10n.cloudSyncUnavailableTitle)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(L10n.cloudSyncUnavailableMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .cardContainer()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("today.cloudSyncNotice")
    }
}

#Preview {
    CloudSyncUnavailableNotice()
        .padding()
}
