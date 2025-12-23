import SwiftUI

public struct TypeBadgeView: View {
    public let text: String
    public let width: CGFloat

    public init(text: String, width: CGFloat = 44) {
        self.text = text
        self.width = width
    }

    public var body: some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .frame(width: width, alignment: .center)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

