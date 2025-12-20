//
//  SlotRow.swift
//  DDiary
//
//  Created by Ilia Khokhlov on 20.12.25.
//

import SwiftUI

@MainActor
public struct SlotRow: View {
    public let title: String
    public let timeText: String
    public let status: SlotStatus
    public let trailingStatusText: String?
    public let onTap: () -> Void
    public let accessibilityId: String
    public let leadingBadgeText: String?
    public let trailingIsSecondary: Bool
    public let titleFontWeight: Font.Weight?
    public let rowVerticalPadding: CGFloat

    public init(
        title: String,
        timeText: String,
        status: SlotStatus,
        trailingStatusText: String? = nil,
        onTap: @escaping () -> Void,
        accessibilityId: String,
        leadingBadgeText: String? = nil,
        trailingIsSecondary: Bool = false,
        titleFontWeight: Font.Weight? = nil,
        rowVerticalPadding: CGFloat = 6
    ) {
        self.title = title
        self.timeText = timeText
        self.status = status
        self.trailingStatusText = trailingStatusText
        self.onTap = onTap
        self.accessibilityId = accessibilityId
        self.leadingBadgeText = leadingBadgeText
        self.trailingIsSecondary = trailingIsSecondary
        self.titleFontWeight = titleFontWeight
        self.rowVerticalPadding = rowVerticalPadding
    }

    public var body: some View {
        Button(action: onTap) {
            HStack(spacing: DS.Spacing.small) {
                StatusDot(status, size: 12)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        if let badge = leadingBadgeText {
                            KindBadgeView(text: badge)
                        }
                        Text(title)
                            .font(.body)
                            .fontWeight(titleFontWeight ?? .regular)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Text(timeText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: DS.Spacing.small)

                Text(trailingStatusText ?? status.localizedTitle)
                    .font(.callout)
                    .foregroundStyle(trailingIsSecondary ? .secondary : status.color)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
            .padding(.vertical, rowVerticalPadding)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityId)
    }
}

private struct KindBadgeView: View {
    let text: String
    // Fixed width to align titles across rows regardless of text length.
    // Chosen to comfortably fit "GLU" at typical Dynamic Type sizes.
    private let width: CGFloat = 36

    var body: some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .frame(width: width, alignment: .center)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

#Preview("SlotRow") {
    VStack(alignment: .leading, spacing: DS.Spacing.small) {
        SlotRow(
            title: String(localized: "Blood Pressure", comment: "Row title for BP slot"),
            timeText: "09:00",
            status: .scheduled,
            onTap: {},
            accessibilityId: "bp_scheduled"
        )
        SlotRow(
            title: UIStrings.glucoseTitle(mealSlot: "breakfast", measurementType: "fingerstick"),
            timeText: "08:00",
            status: .due,
            onTap: {},
            accessibilityId: "glucose_due"
        )
        SlotRow(
            title: UIStrings.glucoseTitle(mealSlot: "lunch", measurementType: "sensor"),
            timeText: "12:00",
            status: .missed,
            onTap: {},
            accessibilityId: "glucose_missed"
        )
        SlotRow(
            title: String(localized: "Blood Pressure", comment: "Row title for BP slot"),
            timeText: "18:30",
            status: .completed,
            onTap: {},
            accessibilityId: "bp_done"
        )
    }
    .padding()
}

