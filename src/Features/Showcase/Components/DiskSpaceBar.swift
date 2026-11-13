import SparkleCore
import SparkleDesignSystem
import SwiftUI

/// Compact remote partition free disk space indicator badge (`statvfs` display).
public struct DiskSpaceBar: View {
    public let diskSpace: MockDiskSpace

    @Environment(\.sparklePalette) private var palette

    public init(diskSpace: MockDiskSpace) {
        self.diskSpace = diskSpace
    }

    private var usageColor: Color {
        if diskSpace.usedFraction >= 0.90 {
            return Color.red
        } else if diskSpace.usedFraction >= 0.80 {
            return Color.orange
        } else {
            return Color.blue
        }
    }

    public var body: some View {
        let tokens = SparkleSemanticTokens(palette: palette)

        HStack(spacing: 8) {
            Image(systemName: "internaldrive.fill")
                .font(.system(size: 11))
                .foregroundStyle(usageColor)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(diskSpace.mountPoint)
                        .font(SparkleSemanticTokens.monoBoldFont)
                        .foregroundStyle(tokens.primaryText)

                    Spacer(minLength: 4)

                    Text(diskSpace.formattedSummary)
                        .font(SparkleSemanticTokens.captionFont)
                        .foregroundStyle(tokens.secondaryText)
                }

                ModernProgressBar(
                    fraction: diskSpace.usedFraction,
                    tint: usageColor,
                    trackTint: tokens.hairlineBorder
                )
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tokens.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(tokens.hairlineBorder, lineWidth: 1)
        )
    }
}
