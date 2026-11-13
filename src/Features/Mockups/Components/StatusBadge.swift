import SparkleCore
import SparkleDesignSystem
import SwiftUI

/// Reusable status badge pill displaying an icon, title, and tint for transfer and connection states.
public struct StatusBadge: View {
    public let title: String
    public let iconName: String
    public let tint: Color
    public let isAnimated: Bool

    public init(
        title: String,
        iconName: String,
        tint: Color,
        isAnimated: Bool = false
    ) {
        self.title = title
        self.iconName = iconName
        self.tint = tint
        self.isAnimated = isAnimated
    }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.system(size: 10, weight: .semibold))
            Text(title)
                .font(SparkleSemanticTokens.captionSemiboldFont)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(tint.opacity(0.14))
        .foregroundStyle(tint)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(tint.opacity(0.28), lineWidth: 0.8)
        )
    }
}
