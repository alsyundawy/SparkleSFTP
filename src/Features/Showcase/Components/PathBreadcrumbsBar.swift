import SparkleCore
import SparkleDesignSystem
import SwiftUI

/// Segmented interactive path breadcrumbs bar inspired by macOS `NSPathControl`.
public struct PathBreadcrumbsBar: View {
    public let path: String
    public let onSelectSubpath: ((String) -> Void)?

    @Environment(\.sparklePalette) private var palette

    public init(path: String, onSelectSubpath: ((String) -> Void)? = nil) {
        self.path = path
        self.onSelectSubpath = onSelectSubpath
    }

    private var segments: [(name: String, fullPath: String)] {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [("/", "/")] }

        let parts = trimmed.split(separator: "/").map(String.init)
        var result: [(name: String, fullPath: String)] = [("Root", "/")]
        var cumulative = ""

        for part in parts {
            cumulative += "/" + part
            result.append((part, cumulative))
        }
        return result
    }

    public var body: some View {
        let tokens = SparkleSemanticTokens(palette: palette)

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 3) {
                ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(tokens.tertiaryText)
                    }

                    Button {
                        onSelectSubpath?(segment.fullPath)
                    } label: {
                        let isLast = index == segments.count - 1
                        let iconName = index == 0 ? "internaldrive" : (isLast ? "folder.fill" : "folder")
                        let font = isLast ? SparkleSemanticTokens.monoBoldFont : SparkleSemanticTokens.monoFont
                        let textTint = isLast ? tokens.primaryText : tokens.secondaryText

                        HStack(spacing: 4) {
                            Image(systemName: iconName)
                                .font(.system(size: 11))
                                .foregroundStyle(isLast ? tokens.accent : tokens.secondaryText)

                            Text(segment.name)
                                .font(font)
                                .foregroundStyle(textTint)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(index == segments.count - 1 ? tokens.accent.opacity(0.12) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
        }
        .frame(height: 28)
        .background(tokens.elevatedHeaderBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(tokens.hairlineBorder, lineWidth: 1)
        )
    }
}
