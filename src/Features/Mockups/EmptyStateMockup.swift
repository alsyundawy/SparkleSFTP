import AppKit
import SparkleCore
import SparkleDesignSystem
import SwiftUI

/// Mockup showcasing clean, macOS 13-compatible empty states across workspace scenarios.
public struct EmptyStateMockup: View {
    @State private var selectedScenario: Scenario = .noSession

    @Environment(\.sparklePalette) private var palette

    public enum Scenario: String, CaseIterable, Identifiable {
        case noSession = "No Remote Session"
        case emptyFolder = "Empty Directory"
        case clearQueue = "Empty Transfer Queue"
        case noSearchResults = "No Filter Matches"

        public var id: String {
            rawValue
        }
    }

    public init() {}

    public var body: some View {
        let tokens = SparkleSemanticTokens(palette: palette)

        VStack(spacing: 0) {
            // Scenario Selector Header
            HStack(spacing: 12) {
                Text("Empty State Scenarios")
                    .font(SparkleSemanticTokens.titleFont)
                    .foregroundStyle(tokens.primaryText)

                Spacer()

                Picker("Scenario", selection: $selectedScenario) {
                    ForEach(Scenario.allCases) { scenario in
                        Text(scenario.rawValue).tag(scenario)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 520)
            }
            .padding(.horizontal, SparkleSemanticTokens.spacingMd)
            .padding(.vertical, SparkleSemanticTokens.spacingSm)
            .background(tokens.elevatedHeaderBackground)

            Divider().overlay(tokens.hairlineBorder)

            // Main Empty State Card
            Group {
                switch selectedScenario {
                case .noSession:
                    EmptyStateView(
                        iconName: "bolt.horizontal.circle",
                        title: "No Active Connection",
                        description: "Connect to an SFTP, SCP, or FTPS server from the Quick Connect bar "
                            + "or choose a saved profile from Connection Manager.",
                        actionTitle: "Open Connection Manager",
                        action: {}
                    )
                case .emptyFolder:
                    EmptyStateView(
                        iconName: "folder.badge.questionmark",
                        title: "Remote Directory Is Empty",
                        description: "The path /var/www/staging contains no files or subdirectories. "
                            + "Drag files here or click Upload to transfer files.",
                        actionTitle: "Upload Files",
                        action: {}
                    )
                case .clearQueue:
                    EmptyStateView(
                        iconName: "checkmark.seal",
                        title: "Transfer Queue Is Clear",
                        description: "All queued uploads and downloads have finished successfully. "
                            + "Select files in either pane and press F5 to begin a new transfer.",
                        actionTitle: "Browse Files",
                        action: {}
                    )
                case .noSearchResults:
                    EmptyStateView(
                        iconName: "magnifyingglass",
                        title: "No Matching Files Found",
                        description: "No files in the current workspace match your search filter criteria. "
                            + "Try adjusting or clearing the active filter.",
                        actionTitle: "Reset Filter",
                        action: {}
                    )
                }
            }
            .sparkleCardStyle(tokens: tokens)
            .padding(SparkleSemanticTokens.spacingLg)
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(tokens.windowBackground)
    }
}

// MARK: - Xcode Previews (1280×800)

#if DEBUG
    struct EmptyStateMockup_Previews: PreviewProvider {
        @MainActor
        static var previews: some View {
            Group {
                EmptyStateMockup()
                    .environment(\.sparklePalette, SparkleThemeCatalog.defaultDark)
                    .preferredColorScheme(.dark)
                    .previewDisplayName("Empty States Dark (1280×800)")

                EmptyStateMockup()
                    .environment(\.sparklePalette, SparkleThemeCatalog.defaultLight)
                    .preferredColorScheme(.light)
                    .previewDisplayName("Empty States Light (1280×800)")
            }
            .frame(width: 1280, height: 800)
        }
    }
#endif
