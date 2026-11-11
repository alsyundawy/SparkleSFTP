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
        let items = buildStripItems()
        HStack(spacing: 6) {
            WorkspaceTabStripRepresentable(
                items: items,
                activeTabID: appState.activeTabID,
                palette: palette,
                strings: appState.strings,
                onSelect: { tabID in
                    if let pendingURL = appState.selectWorkspaceTabSync(id: tabID) {
                        Task { await appState.refreshLocalDirectory(pendingURL, recordHistory: false) }
                    }
                },
                onClose: { tabID in
                    let outcome = appState.closeWorkspaceTabSync(id: tabID)
                    if outcome.removedSessionID != nil || outcome.pendingLocalRefresh != nil {
                        Task {
                            if let removedID = outcome.removedSessionID {
                                await appState.disconnect(sessionID: removedID)
                            }
                            if let localURL = outcome.pendingLocalRefresh {
                                await appState.refreshLocalDirectory(localURL, recordHistory: false)
                            }
                        }
                    }
                },
                onNewTab: { _ = appState.openNewWorkspaceTab() },
                onDuplicateTab: { tabID in
                    Task { await appState.duplicateWorkspaceTab(id: tabID) }
                },
                onReconnectTab: { tabID in
                    Task { await appState.reconnectWorkspaceTab(id: tabID) }
                },
                onOpenNewWindow: { tabID in
                    if let tab = appState.workspaceTabs.first(where: { $0.id == tabID }),
                       let sessionID = tab.sessionID,
                       let session = appState.activeSessions.first(where: { $0.id == sessionID }) {
                        appState.openProfileInNewWindow(session.profile.id)
                    }
                },
                onCloseOtherTabs: { tabID in
                    Task { await appState.closeOtherWorkspaceTabs(keeping: tabID) }
                }
            )
            .frame(minWidth: 0, maxWidth: .infinity)
            .frame(height: 34)

            Button {
                _ = appState.openNewWorkspaceTab()
            } label: {
                Image(systemName: "plus")
                    .font(.caption.weight(.semibold))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(appState.strings.t("tabs.newTab"))
            .accessibilityLabel(appState.strings.t("tabs.newTab"))

            Toggle(isOn: $appState.isQuickConnectBarVisible) {
                Label(appState.strings.t("tabs.quickConnectToggle"), systemImage: "bolt.horizontal.fill")
                    .labelStyle(.titleAndIcon)
                    .font(SparkleTheme.Typography.caption)
            }
            .toggleStyle(.button)
            .controlSize(.small)
            .fixedSize()
            .help(appState.strings.t("tabs.quickConnectToggle"))
        }
        .padding(.horizontal, SparkleTheme.Spacing.small)
        .frame(minWidth: 0, maxWidth: .infinity)
        .frame(height: 36)
        .clipped()
        .background(palette.windowColor)
        .overlay(alignment: .bottom) {
            palette.borderColor.frame(height: 1)
        }
    }

    private func buildStripItems() -> [WorkspaceTabStripItem] {
        let canCloseOthers = appState.workspaceTabs.count > 1
        return appState.workspaceTabs.map { tab in
            let session = appState.activeSessions.first { $0.id == tab.sessionID }
            let subtitle = session.map { "(\($0.profile.username)@\($0.profile.host))" }
            return WorkspaceTabStripItem(
                id: tab.id,
                title: tab.title,
                subtitle: subtitle,
                isConnected: session != nil,
                isEncrypted: session?.profile.protocolType.isEncryptedByDefault ?? false,
                isActive: appState.activeTabID == tab.id,
                canClose: appState.workspaceTabs.count > 1 || session != nil,
                canCloseOthers: canCloseOthers
            )
        }
    }
}
