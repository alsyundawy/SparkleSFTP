import AppKit
import SparkleCore
import SparkleDesignSystem
import SwiftUI

/// High-fidelity File Conflict Resolution dialog mockup supporting Overwrite, Resume, Skip, and Rename comparison.
public struct ConflictDialogMockup: View {
    @State private var selectedAction: ConflictAction = .overwriteIfNewer
    @State private var applyToAllInBatch: Bool = false
    @State private var customRenameText: String = "nginx_access (2).log"

    @Environment(\.sparklePalette) private var palette

    public enum ConflictAction: String, CaseIterable, Identifiable {
        case overwrite = "Overwrite"
        case overwriteIfNewer = "Overwrite if Newer"
        case resume = "Resume Partial"
        case rename = "Rename Target"
        case skip = "Skip File"

        public var id: String {
            rawValue
        }

        public var description: String {
            switch self {
            case .overwrite: return "Replace the existing destination file completely."
            case .overwriteIfNewer: return "Replace only if source timestamp is more recent."
            case .resume: return "Append remaining bytes starting from existing offset."
            case .rename: return "Keep both files by saving with a modified name."
            case .skip: return "Leave destination intact and move to the next item."
            }
        }

        public var iconName: String {
            switch self {
            case .overwrite: return "arrow.triangle.2.circlepath.doc.on.clipboard"
            case .overwriteIfNewer: return "clock.arrow.2.circlepath"
            case .resume: return "arrow.forward.to.line"
            case .rename: return "pencil.line"
            case .skip: return "forward.end.fill"
            }
        }
    }

    public init() {}

    public var body: some View {
        let tokens = SparkleSemanticTokens(palette: palette)

        ZStack {
            // Simulated workspace backdrop
            tokens.windowBackground
                .ignoresSafeArea()

            // Modal Dialog Card
            VStack(alignment: .leading, spacing: SparkleSemanticTokens.spacingLg) {
                // Header
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 20))
                        .frame(width: 40, height: 40)
                        .background(Color.orange.opacity(0.15))
                        .foregroundStyle(Color.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text("Target File Already Exists")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(tokens.primaryText)

                            StatusBadge(title: "Conflict 1 of 3", iconName: "exclamationmark.2", tint: .purple)
                        }

                        Text("Choose how SparkleSFTP should resolve this collision for nginx_access.log")
                            .font(SparkleSemanticTokens.bodyFont)
                            .foregroundStyle(tokens.secondaryText)
                    }

                    Spacer()
                }

                Divider().overlay(tokens.hairlineBorder)

                // Source vs Destination Side-by-Side Comparison
                HStack(spacing: SparkleSemanticTokens.spacingMd) {
                    fileComparisonCard(
                        info: FileComparisonInfo(
                            roleTitle: "SOURCE (REMOTE)",
                            badgeText: "Newer (+1.8 MB)",
                            badgeTint: .blue,
                            path: "/var/log/nginx/access.log",
                            size: "42,540,112 bytes (40.5 MB)",
                            modified: "2026-11-12 22:28:14 UTC",
                            permissions: "-rw-r----- (0640)"
                        ),
                        tokens: tokens
                    )

                    Image(systemName: "arrow.right")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(tokens.tertiaryText)

                    fileComparisonCard(
                        info: FileComparisonInfo(
                            roleTitle: "DESTINATION (LOCAL)",
                            badgeText: "Existing",
                            badgeTint: .gray,
                            path: "/Users/developer/Logs/nginx_access.log",
                            size: "40,710,400 bytes (38.8 MB)",
                            modified: "2026-11-12 18:10:02 UTC",
                            permissions: "-rw-r--r-- (0644)"
                        ),
                        tokens: tokens
                    )
                }

                // Action Selection Options
                VStack(alignment: .leading, spacing: 8) {
                    Text("Resolution Action")
                        .font(SparkleSemanticTokens.captionSemiboldFont)
                        .foregroundStyle(tokens.secondaryText)

                    VStack(spacing: 4) {
                        ForEach(ConflictAction.allCases) { action in
                            let isSelected = (selectedAction == action)
                            Button {
                                selectedAction = action
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                                        .font(.system(size: 13))
                                        .foregroundStyle(isSelected ? tokens.accent : tokens.tertiaryText)

                                    Image(systemName: action.iconName)
                                        .font(.system(size: 11))
                                        .sparkleIconContainer(tint: isSelected ? tokens.accent : tokens.secondaryText)

                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(action.rawValue)
                                            .font(SparkleSemanticTokens.captionSemiboldFont)
                                            .foregroundStyle(tokens.primaryText)
                                        Text(action.description)
                                            .font(.system(size: 10))
                                            .foregroundStyle(tokens.secondaryText)
                                    }

                                    Spacer()
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(
                                        cornerRadius: SparkleSemanticTokens.rowCornerRadius,
                                        style: .continuous
                                    )
                                    .fill(isSelected ? tokens.rowSelectionBackground : Color.clear)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if selectedAction == .rename {
                        HStack(spacing: 8) {
                            Text("New filename:")
                                .font(SparkleSemanticTokens.captionFont)
                                .foregroundStyle(tokens.secondaryText)
                            TextField("Filename", text: $customRenameText)
                                .textFieldStyle(.roundedBorder)
                                .font(SparkleSemanticTokens.monoFont)
                        }
                        .padding(.top, 4)
                    }
                }

                Divider().overlay(tokens.hairlineBorder)

                // Footer Controls
                HStack {
                    Toggle("Apply to all remaining conflicts in this queue (2 left)", isOn: $applyToAllInBatch)
                        .toggleStyle(.checkbox)
                        .font(SparkleSemanticTokens.captionFont)
                        .foregroundStyle(tokens.secondaryText)

                    Spacer()

                    Button("Cancel Queue") {}
                        .buttonStyle(.bordered)

                    Button("Continue Transfer") {}
                        .buttonStyle(.borderedProminent)
                        .tint(tokens.accent)
                }
            }
            .padding(20)
            .frame(width: 720)
            .sparkleCardStyle(tokens: tokens)
            .shadow(color: Color.black.opacity(palette.isDark ? 0.45 : 0.15), radius: 24, y: 10)
        }
        .frame(minWidth: 900, minHeight: 620)
    }

    private struct FileComparisonInfo {
        let roleTitle: String
        let badgeText: String
        let badgeTint: Color
        let path: String
        let size: String
        let modified: String
        let permissions: String
    }

    private func fileComparisonCard(
        info: FileComparisonInfo,
        tokens: SparkleSemanticTokens
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(info.roleTitle)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(tokens.tertiaryText)
                Spacer()
                StatusBadge(title: info.badgeText, iconName: "info.circle.fill", tint: info.badgeTint)
            }

            Text(info.path)
                .font(SparkleSemanticTokens.monoFont)
                .foregroundStyle(tokens.primaryText)
                .lineLimit(2)
                .truncationMode(.middle)

            Divider().overlay(tokens.hairlineBorder)

            VStack(alignment: .leading, spacing: 4) {
                metadataLine(label: "Size:", value: info.size, tokens: tokens)
                metadataLine(label: "Modified:", value: info.modified, tokens: tokens)
                metadataLine(label: "Mode:", value: info.permissions, tokens: tokens)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tokens.windowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(tokens.hairlineBorder, lineWidth: 1))
    }

    private func metadataLine(label: String, value: String, tokens: SparkleSemanticTokens) -> some View {
        HStack {
            Text(label)
                .font(SparkleSemanticTokens.captionFont)
                .foregroundStyle(tokens.tertiaryText)
                .frame(width: 58, alignment: .leading)
            Text(value)
                .font(SparkleSemanticTokens.monoFont)
                .foregroundStyle(tokens.secondaryText)
        }
    }
}

// MARK: - Xcode Previews (1280×800)

#if DEBUG
    struct ConflictDialogMockup_Previews: PreviewProvider {
        @MainActor
        static var previews: some View {
            Group {
                ConflictDialogMockup()
                    .environment(\.sparklePalette, SparkleThemeCatalog.defaultDark)
                    .preferredColorScheme(.dark)
                    .previewDisplayName("Conflict Dialog Dark (1280×800)")

                ConflictDialogMockup()
                    .environment(\.sparklePalette, SparkleThemeCatalog.defaultLight)
                    .preferredColorScheme(.light)
                    .previewDisplayName("Conflict Dialog Light (1280×800)")
            }
            .frame(width: 1280, height: 800)
        }
    }
#endif
