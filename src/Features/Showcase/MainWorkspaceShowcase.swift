import AppKit
import SparkleCore
import SparkleDesignSystem
import SwiftUI

/// High-fidelity native macOS dual-pane commander workspace showcase ("Sparkle Commander" visual refresh).
public struct MainWorkspaceShowcase: View {
    @State private var activeTabID: Int = 1
    @State private var selectedLeftFileID: String? = "Package.swift"
    @State private var selectedRightFileID: String? = "access.log"
    @State private var leftPath: String = "/Users/developer/Projects/SparkleSFTP"
    @State private var rightPath: String = "/var/log/nginx"
    @State private var isTransferDrawerExpanded: Bool = false

    @Environment(\.sparklePalette) private var palette

    public init() {}

    public var body: some View {
        let tokens = SparkleSemanticTokens(palette: palette)

        VStack(spacing: 0) {
            // MARK: - Workspace Tab Strip

            workspaceTabBar(tokens: tokens)

            // MARK: - Quick Connect Bar

            quickConnectBar(tokens: tokens)

            Divider()
                .overlay(tokens.hairlineBorder)

            // MARK: - Dual Pane Commander

            HStack(spacing: SparkleSemanticTokens.spacingMd) {
                // Left Pane: Local Files
                MainWorkspacePaneView(
                    config: FilePaneConfig(
                        title: "Local Workspace",
                        iconName: "laptopcomputer",
                        path: leftPath,
                        diskSpace: MockData.localDiskSpace,
                        items: MockData.localMacOSFiles
                    ),
                    selectedID: $selectedLeftFileID,
                    tokens: tokens
                )

                // Central Transfer Action Column
                transferActionDivider(tokens: tokens)

                // Right Pane: Remote Files
                MainWorkspacePaneView(
                    config: FilePaneConfig(
                        title: "Ubuntu Production (SFTP)",
                        iconName: "server.rack",
                        path: rightPath,
                        diskSpace: MockData.remoteDiskSpace,
                        items: MockData.remoteLinuxFiles
                    ),
                    selectedID: $selectedRightFileID,
                    tokens: tokens
                )
            }
            .padding(SparkleSemanticTokens.spacingMd)

            Spacer(minLength: 0)

            // MARK: - Bottom Minimized Transfer Drawer & Status Bar

            transferDrawerBar(tokens: tokens)
            statusBar(tokens: tokens)
        }
        .frame(minWidth: 1000, minHeight: 680)
        .background(tokens.windowBackground)
    }

    // MARK: - Workspace Tab Bar

    private func workspaceTabBar(tokens: SparkleSemanticTokens) -> some View {
        HStack(spacing: 4) {
            tabButton(id: 1, title: "Production Web (SFTP)", icon: "lock.shield.fill", badge: "22", tokens: tokens)
            tabButton(id: 2, title: "FreeBSD Staging (SCP)", icon: "terminal.fill", badge: "2222", tokens: tokens)
            tabButton(id: 3, title: "Archive NAS (FTPS)", icon: "lock.fill", badge: "990", tokens: tokens)

            Button {} label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(tokens.secondaryText)
                    .frame(width: 24, height: 24)
                    .background(tokens.hairlineBorder)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)

            Spacer()
        }
        .padding(.horizontal, SparkleSemanticTokens.spacingSm)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .background(tokens.elevatedHeaderBackground)
    }

    private func tabButton(
        id: Int,
        title: String,
        icon: String,
        badge: String,
        tokens: SparkleSemanticTokens
    ) -> some View {
        let isSelected = (activeTabID == id)
        return Button {
            activeTabID = id
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? tokens.accent : tokens.secondaryText)

                Text(title)
                    .font(isSelected ? SparkleSemanticTokens.captionSemiboldFont : SparkleSemanticTokens.captionFont)
                    .foregroundStyle(isSelected ? tokens.primaryText : tokens.secondaryText)

                Text(badge)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(tokens.accent.opacity(isSelected ? 0.2 : 0.08))
                    .foregroundStyle(isSelected ? tokens.accent : tokens.secondaryText)
                    .clipShape(Capsule())

                if isSelected {
                    Button {} label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(tokens.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 2)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? tokens.cardBackground : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isSelected ? tokens.hairlineBorder : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Quick Connect Bar

    private func quickConnectBar(tokens: SparkleSemanticTokens) -> some View {
        HStack(spacing: SparkleSemanticTokens.spacingSm) {
            Label("Quick Connect:", systemImage: "bolt.fill")
                .font(SparkleSemanticTokens.captionSemiboldFont)
                .foregroundStyle(tokens.accent)

            quickConnectField(label: "Host:", value: "web-01.eu-west.internal", tokens: tokens)
            quickConnectField(label: "User:", value: "deploy", tokens: tokens)
            quickConnectField(label: "Port:", value: "22", tokens: tokens)

            StatusBadge(title: "SFTP v3", iconName: "lock.shield.fill", tint: .blue)

            Spacer()

            Button {} label: {
                Label("Disconnect", systemImage: "xmark.circle.fill")
                    .font(SparkleSemanticTokens.captionFont)
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
        .padding(.horizontal, SparkleSemanticTokens.spacingMd)
        .padding(.vertical, 6)
        .background(tokens.windowBackground)
    }

    private func quickConnectField(label: String, value: String, tokens: SparkleSemanticTokens) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(SparkleSemanticTokens.captionFont)
                .foregroundStyle(tokens.secondaryText)
            Text(value)
                .font(SparkleSemanticTokens.monoFont)
                .foregroundStyle(tokens.primaryText)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tokens.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(tokens.hairlineBorder, lineWidth: 1))
    }

    // MARK: - Transfer Action Divider Column

    private func transferActionDivider(tokens: SparkleSemanticTokens) -> some View {
        VStack(spacing: 12) {
            Spacer()

            actionButton(title: "Upload", icon: "arrow.right.circle.fill", tint: tokens.accent, tokens: tokens)
            actionButton(title: "Download", icon: "arrow.left.circle.fill", tint: tokens.accent, tokens: tokens)
            actionButton(title: "Sync", icon: "arrow.triangle.2.circlepath", tint: tokens.secondaryText, tokens: tokens)

            Spacer()
        }
        .frame(width: 60)
    }

    private func actionButton(
        title: String,
        icon: String,
        tint: Color,
        tokens: SparkleSemanticTokens
    ) -> some View {
        Button {} label: {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                Text(title)
                    .font(SparkleSemanticTokens.captionSemiboldFont)
            }
            .frame(width: 54, height: 48)
            .background(tokens.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(tokens.hairlineBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint)
    }

    // MARK: - Transfer Drawer Bar

    private func transferDrawerBar(tokens: SparkleSemanticTokens) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.up.arrow.down.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(tokens.accent)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("Transfer Queue (2 active, 1 queued)")
                        .font(SparkleSemanticTokens.captionSemiboldFont)
                        .foregroundStyle(tokens.primaryText)

                    Text("14.8 MB/s · ETA: 00:01:42")
                        .font(SparkleSemanticTokens.monoFont)
                        .foregroundStyle(tokens.secondaryText)
                }

                ModernProgressBar(fraction: 0.68, tint: tokens.accent)
            }
            .frame(maxWidth: 420)

            Spacer()

            StatusBadge(title: "Active", iconName: "arrow.triangle.2.circlepath", tint: .blue)

            Button {
                isTransferDrawerExpanded.toggle()
            } label: {
                Image(systemName: isTransferDrawerExpanded ? "chevron.down" : "chevron.up")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tokens.secondaryText)
                    .padding(4)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, SparkleSemanticTokens.spacingMd)
        .padding(.vertical, 6)
        .background(tokens.cardBackground)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(tokens.hairlineBorder),
            alignment: .top
        )
    }

    // MARK: - Status Bar

    private func statusBar(tokens: SparkleSemanticTokens) -> some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 7, height: 7)
                Text("Connected: web-01.eu-west.internal (42 ms)")
                    .font(SparkleSemanticTokens.captionFont)
                    .foregroundStyle(tokens.secondaryText)
            }

            Spacer()

            HStack(spacing: 12) {
                Text("UTF-8")
                    .font(SparkleSemanticTokens.monoFont)
                    .foregroundStyle(tokens.tertiaryText)

                Text("F5 Copy · F6 Move · F7 Mkdir · F8 Delete")
                    .font(SparkleSemanticTokens.captionFont)
                    .foregroundStyle(tokens.secondaryText)
            }
        }
        .padding(.horizontal, SparkleSemanticTokens.spacingMd)
        .padding(.vertical, 4)
        .background(tokens.elevatedHeaderBackground)
    }
}

public typealias MainWorkspaceMockup = MainWorkspaceShowcase

// MARK: - Xcode Previews (1280×800)

#if DEBUG
    struct MainWorkspaceShowcase_Previews: PreviewProvider {
        @MainActor
        static var previews: some View {
            Group {
                MainWorkspaceShowcase()
                    .environment(\.sparklePalette, SparkleThemeCatalog.defaultDark)
                    .preferredColorScheme(.dark)
                    .previewDisplayName("Sparkle Commander Dark (1280×800)")

                MainWorkspaceShowcase()
                    .environment(\.sparklePalette, SparkleThemeCatalog.defaultLight)
                    .preferredColorScheme(.light)
                    .previewDisplayName("Sparkle Commander Light (1280×800)")
            }
            .frame(width: 1280, height: 800)
        }
    }
#endif
