import SparkleCore
import SparkleDesignSystem
import SwiftUI

public struct WorkspaceTabBar: View {
    @ObservedObject var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        let palette = appState.activePalette
        HStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(appState.workspaceTabs) { tab in
                        WorkspaceTabItemView(appState: appState, tab: tab, palette: palette)
                    }
                }
                .padding(.vertical, 4)
            }

            Button {
                _ = appState.openNewWorkspaceTab()
            } label: {
                Image(systemName: "plus")
                    .font(.caption.weight(.semibold))
                    .frame(width: 24, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help(appState.strings.t("tabs.newTab"))

            Toggle(isOn: $appState.isQuickConnectBarVisible) {
                Label(appState.strings.t("tabs.quickConnectToggle"), systemImage: "bolt.horizontal.fill")
                    .labelStyle(.titleAndIcon)
                    .font(SparkleTheme.Typography.caption)
            }
            .toggleStyle(.button)
            .controlSize(.small)
            .help(appState.strings.t("tabs.quickConnectToggle"))
        }
        .padding(.horizontal, SparkleTheme.Spacing.small)
        .background(palette.windowColor)
        .overlay(alignment: .bottom) {
            palette.borderColor.frame(height: 1)
        }
    }
}

private struct WorkspaceTabItemView: View {
    @ObservedObject var appState: AppState
    let tab: WorkspaceTab
    let palette: SparkleThemePalette

    @State private var isTabHovered = false
    @State private var isCloseHovered = false

    var body: some View {
        let isActive = appState.activeTabID == tab.id
        let session = appState.activeSessions.first { $0.id == tab.sessionID }
        let canClose = appState.workspaceTabs.count > 1 || session != nil

        HStack(spacing: 2) {
            Button {
                Task { await appState.selectWorkspaceTab(id: tab.id) }
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(
                            session != nil
                                ? SparkleTheme.Colors.encryptedBadge
                                : palette.secondaryTextColor.opacity(0.45)
                        )
                        .frame(width: 6, height: 6)

                    tabProtocolIcon(session: session)

                    Text(tab.title)
                        .font(SparkleTheme.Typography.caption.weight(isActive ? .semibold : .regular))
                        .foregroundStyle(palette.primaryTextColor)
                        .lineLimit(1)

                    if isActive, let session {
                        Text("(\(session.profile.username)@\(session.profile.host))")
                            .font(SparkleTheme.Typography.monoSmall)
                            .foregroundStyle(palette.secondaryTextColor)
                            .lineLimit(1)
                    }
                }
                .padding(.leading, 8)
                .padding(.trailing, canClose ? 4 : 8)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if canClose {
                Button {
                    Task { await appState.closeWorkspaceTab(id: tab.id) }
                } label: {
                    Image(systemName: isCloseHovered ? "xmark.circle.fill" : "xmark")
                        .font(.system(size: isCloseHovered ? 11 : 9, weight: .bold))
                        .foregroundStyle(isCloseHovered ? palette.primaryTextColor : palette.secondaryTextColor)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 4)
                .onHover { isCloseHovered = $0 }
                .help(appState.strings.t("tabs.closeTab"))
            }
        }
        .background(backgroundColor(isActive: isActive))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isActive ? palette.accentColor.opacity(0.85) : palette.borderColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onHover { isTabHovered = $0 }
        .contextMenu {
            tabContextMenu(session: session)
        }
    }

    private func backgroundColor(isActive: Bool) -> Color {
        if isActive {
            return palette.accentColor.opacity(palette.isDark ? 0.30 : 0.18)
        }
        if isTabHovered {
            return palette.accentColor.opacity(palette.isDark ? 0.14 : 0.08)
        }
        return palette.canvasColor
    }

    @ViewBuilder
    private func tabProtocolIcon(session: ActiveSessionModel?) -> some View {
        if let session {
            let encrypted = session.profile.protocolType.isEncryptedByDefault
            Image(systemName: encrypted ? SparkleTheme.Symbols.sftp : SparkleTheme.Symbols.ftpInsecure)
                .font(.caption)
                .foregroundStyle(encrypted ? palette.accentColor : SparkleTheme.Colors.danger)
        } else {
            Image(systemName: "bolt.horizontal")
                .font(.caption)
                .foregroundStyle(palette.secondaryTextColor)
        }
    }

    @ViewBuilder
    private func tabContextMenu(session: ActiveSessionModel?) -> some View {
        let strings = appState.strings
        Button(strings.t("tabs.newTab")) {
            _ = appState.openNewWorkspaceTab()
        }
        Button(strings.t("tabs.duplicateTab")) {
            Task { await appState.duplicateWorkspaceTab(id: tab.id) }
        }
        if let session {
            Button(strings.t("tabs.reconnect")) {
                Task { await appState.reconnectWorkspaceTab(id: tab.id) }
            }
            Button(strings.t("conn.connectNewWindow")) {
                appState.openProfileInNewWindow(session.profile.id)
            }
        }
        Divider()
        Button(strings.t("tabs.closeTab")) {
            Task { await appState.closeWorkspaceTab(id: tab.id) }
        }
        Button(strings.t("tabs.closeOtherTabs")) {
            Task { await appState.closeOtherWorkspaceTabs(keeping: tab.id) }
        }
        .disabled(appState.workspaceTabs.count <= 1)
    }
}
