import SparkleCore
import SparkleDesignSystem
import SwiftUI

/// Centered symbol, title, description, and primary action button (macOS 13+ compatible).
public struct EmptyStateView: View {
    public let iconName: String
    public let title: String
    public let description: String
    public let actionTitle: String?
    public let action: (() -> Void)?

    @Environment(\.sparklePalette) private var palette

    public init(
        iconName: String,
        title: String,
        description: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.iconName = iconName
        self.title = title
        self.description = description
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        let tokens = SparkleSemanticTokens(palette: palette)

        VStack(spacing: 16) {
            Image(systemName: iconName)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(tokens.accent.opacity(0.85))
                .padding(20)
                .background(
                    Circle()
                        .fill(tokens.accent.opacity(0.10))
                )

            VStack(spacing: 6) {
                Text(title)
                    .font(SparkleSemanticTokens.titleFont)
                    .foregroundStyle(tokens.primaryText)

                Text(description)
                    .font(SparkleSemanticTokens.bodyFont)
                    .foregroundStyle(tokens.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(SparkleSemanticTokens.bodyFont)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(tokens.accent)
                .padding(.top, 4)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
