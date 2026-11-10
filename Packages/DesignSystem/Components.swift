import SwiftUI

public struct StatusPill: View {
    public let title: String
    public let systemImage: String
    public let tint: Color

    public init(title: String, systemImage: String, tint: Color) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
    }

    public var body: some View {
        Label(title, systemImage: systemImage)
            .font(SparkleTheme.Typography.caption)
            .padding(.horizontal, SparkleTheme.Spacing.small)
            .padding(.vertical, 3)
            .background(tint.opacity(0.14))
            .foregroundStyle(tint)
            .clipShape(Capsule())
    }
}

public struct SecurityWarningBanner: View {
    public let message: String

    public init(message: String) {
        self.message = message
    }

    public var body: some View {
        HStack(spacing: SparkleTheme.Spacing.small) {
            Image(systemName: SparkleTheme.Symbols.ftpInsecure)
                .foregroundStyle(SparkleTheme.Colors.danger)
            Text(message)
                .font(SparkleTheme.Typography.caption)
                .foregroundStyle(SparkleTheme.Colors.danger)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, SparkleTheme.Spacing.medium)
        .padding(.vertical, SparkleTheme.Spacing.tiny)
        .background(SparkleTheme.Colors.danger.opacity(0.1))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(SparkleTheme.Colors.danger.opacity(0.25)),
            alignment: .bottom
        )
        .accessibilityElement(children: .combine)
    }
}

public struct TransferProgressBar: View {
    public let fraction: Double
    public let tint: Color

    public init(fraction: Double, tint: Color = SparkleTheme.Colors.accent) {
        self.fraction = min(1.0, max(0.0, fraction))
        self.tint = tint
    }

    public var body: some View {
        ProgressView(value: fraction)
            .progressViewStyle(.linear)
            .tint(tint)
    }
}
