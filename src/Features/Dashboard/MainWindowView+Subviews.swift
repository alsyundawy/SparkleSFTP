import SparkleCore
import SparkleDesignSystem
import SwiftUI

struct MainWindowMinimizedActivityLogBar: View {
    @ObservedObject var appState: AppState

    var body: some View {
        HStack {
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    appState.isActivityLogVisible = true
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                    Text(appState.strings.t("activityLog.showLog"))
                        .font(SparkleTheme.Typography.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 3)
                .background(appState.activePalette.windowColor)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(appState.activePalette.borderColor.opacity(0.8), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .help(appState.strings.t("activityLog.showLogTooltip"))
            Spacer()
        }
        .padding(.vertical, 2)
        .background(appState.activePalette.windowColor.opacity(0.85))
    }
}

struct MainWindowMinimizedTransferBar: View {
    @ObservedObject var appState: AppState

    var body: some View {
        HStack {
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    appState.isTransferDrawerVisible = true
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10, weight: .bold))
                    Text(
                        appState.strings.t("transfers.showQueue")
                            + (appState.transferSnapshots.isEmpty ? "" : " (\(appState.transferSnapshots.count))")
                    )
                    .font(SparkleTheme.Typography.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 3)
                .background(appState.activePalette.windowColor)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(appState.activePalette.borderColor.opacity(0.8), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .help(appState.strings.t("transfers.showQueueTooltip"))
            Spacer()
        }
        .padding(.vertical, 2)
        .background(appState.activePalette.windowColor.opacity(0.85))
    }
}

struct MainWindowStatusBar: View {
    @ObservedObject var appState: AppState

    var body: some View {
        let palette = appState.activePalette
        return HStack(spacing: SparkleTheme.Spacing.medium) {
            if let session = appState.currentSession {
                StatusPill(
                    title: session.profile.protocolType.displayName,
                    systemImage: session.profile.protocolType.isEncryptedByDefault
                        ? SparkleTheme.Symbols.sftp
                        : SparkleTheme.Symbols.ftpInsecure,
                    tint: session.profile.protocolType.isEncryptedByDefault
                        ? SparkleTheme.Colors.encryptedBadge
                        : SparkleTheme.Colors.danger
                )
                Text("\(session.profile.username)@\(session.profile.host):\(session.profile.port)")
                    .font(SparkleTheme.Typography.monoSmall)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text(appState.strings.t("nav.disconnected"))
                    .font(SparkleTheme.Typography.caption)
                    .foregroundStyle(palette.secondaryTextColor)
                    .lineLimit(1)
            }

            if let message = appState.statusBannerMessage {
                Text("· \(message)")
                    .font(SparkleTheme.Typography.caption)
                    .foregroundStyle(palette.secondaryTextColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 8)

            Text(palette.displayName)
                .font(SparkleTheme.Typography.caption)
                .foregroundStyle(palette.secondaryTextColor)
                .lineLimit(1)

            Button {
                Task { await appState.toggleTerminalDrawerForActiveTab() }
            } label: {
                Label(appState.strings.t("nav.terminal"), systemImage: SparkleTheme.Symbols.terminal)
            }
            .buttonStyle(.bordered)
            .tint(appState.isTerminalVisible ? palette.accentColor : palette.secondaryTextColor)
            .controlSize(.small)
            .fixedSize()
            .disabled(appState.currentSession?.sshClient == nil && !appState.isTerminalVisible)

            Toggle(appState.strings.t("activityLog.title"), isOn: $appState.isActivityLogVisible)
                .toggleStyle(.button)
                .controlSize(.small)
                .fixedSize()
                .help(appState.strings.t("activityLog.toggleTooltip"))

            Toggle(appState.strings.t("nav.transfers"), isOn: $appState.isTransferDrawerVisible)
                .toggleStyle(.button)
                .controlSize(.small)
                .fixedSize()
                .help(appState.strings.t("transfers.showQueueTooltip"))

            languageMenuSelector
                .controlSize(.small)
                .fixedSize()
        }
        .padding(.horizontal, SparkleTheme.Spacing.medium)
        .padding(.vertical, SparkleTheme.Spacing.tiny)
        .frame(minWidth: 0, maxWidth: .infinity)
        .frame(height: 28)
        .background(palette.windowColor)
    }

    private var languageMenuSelector: some View {
        Menu {
            ForEach(appState.availableLocales) { doc in
                Button {
                    appState.selectLocale(code: doc.code)
                } label: {
                    if appState.activeLocaleCode == doc.code {
                        Label("\(doc.displayName) (\(doc.code.uppercased()))", systemImage: "checkmark")
                    } else {
                        Text("\(doc.displayName) (\(doc.code.uppercased()))")
                    }
                }
            }
        } label: {
            Label(appState.activeLocaleCode.uppercased(), systemImage: "globe")
        }
    }
}

extension MainWindowView {
    var minimizedActivityLogBar: some View {
        MainWindowMinimizedActivityLogBar(appState: appState)
    }

    var minimizedTransferBar: some View {
        MainWindowMinimizedTransferBar(appState: appState)
    }

    var statusBar: some View {
        MainWindowStatusBar(appState: appState)
    }

    var groupedThemeFamilies: [String] {
        var families: [String] = []
        for theme in appState.availableThemes where !families.contains(theme.family) {
            families.append(theme.family)
        }
        return families
    }

    var languageMenuSelector: some View {
        Menu {
            ForEach(appState.availableLocales) { doc in
                Button {
                    appState.selectLocale(code: doc.code)
                } label: {
                    if appState.activeLocaleCode == doc.code {
                        Label("\(doc.displayName) (\(doc.code.uppercased()))", systemImage: "checkmark")
                    } else {
                        Text("\(doc.displayName) (\(doc.code.uppercased()))")
                    }
                }
            }
        } label: {
            Label(appState.activeLocaleCode.uppercased(), systemImage: "globe")
        }
    }

    var themeSelectionMenu: some View {
        Menu {
            ForEach(groupedThemeFamilies, id: \.self) { family in
                Menu(family) {
                    ForEach(appState.availableThemes.filter { $0.family == family }) { theme in
                        Button {
                            appState.selectTheme(theme)
                        } label: {
                            if appState.activePalette.id == theme.id {
                                Label(theme.displayName, systemImage: "checkmark")
                            } else {
                                Text(theme.displayName)
                            }
                        }
                    }
                }
            }
        } label: {
            Label(appState.strings.t("prefs.tabThemes"), systemImage: SparkleTheme.Symbols.theme)
        }
        .help(appState.activePalette.displayName)
    }

    func detailContentView(palette: SparkleThemePalette) -> some View {
        VStack(spacing: 0) {
            WorkspaceTabBar(appState: appState)

            if appState.isQuickConnectAvailable, appState.isQuickConnectBarVisible {
                QuickConnectBar(appState: appState)
                    .accessibilityIdentifier("quickConnectBar")
            }

            if !appState.isActivityLogVisible {
                minimizedActivityLogBar
            }

            VSplitView {
                if appState.isActivityLogVisible {
                    ActivityLogView(appState: appState)
                        .frame(minHeight: 70, idealHeight: 130)
                }

                DualPaneCommanderView(appState: appState)
                    .frame(minHeight: 180, idealHeight: 420)

                if appState.isTerminalVisible {
                    TerminalWorkspaceView(appState: appState)
                        .frame(minHeight: 120, idealHeight: 180)
                }

                if appState.isTransferDrawerVisible {
                    TransferQueueView(appState: appState)
                        .frame(minHeight: 90, idealHeight: 150)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !appState.isTransferDrawerVisible {
                minimizedTransferBar
            }

            statusBar
        }
        .navigationSplitViewColumnWidth(min: 520, ideal: 920)
        .clipped()
        .background(palette.windowColor, ignoresSafeAreaEdges: [])
        .foregroundStyle(palette.primaryTextColor)
        .tint(palette.accentColor)
    }
}
