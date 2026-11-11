import SparkleCore
import SparkleDesignSystem
import SwiftUI

public struct MainWindowView: View {
    @ObservedObject var appState: AppState
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var editorMode: ConnectionEditorMode?
    @State private var isShowingSecurityDiagnostics = false

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        let palette = appState.activePalette
        NavigationSplitView {
            ConnectionManagerView(
                appState: appState,
                editorMode: $editorMode
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
        } detail: {
            VStack(spacing: 0) {
                WorkspaceTabBar(appState: appState)

                if appState.isQuickConnectAvailable, appState.isQuickConnectBarVisible {
                    QuickConnectBar(appState: appState)
                        .accessibilityIdentifier("quickConnectBar")
                }

                VSplitView {
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

                statusBar
            }
            .navigationSplitViewColumnWidth(min: 520, ideal: 920)
            .clipped()
            .background(palette.windowColor)
            .foregroundStyle(palette.primaryTextColor)
            .tint(palette.accentColor)
        }
        .frame(
            minWidth: 820,
            idealWidth: 1240,
            maxWidth: .infinity,
            minHeight: 540,
            idealHeight: 780,
            maxHeight: .infinity
        )
        .preferredColorScheme(
            appState.appearanceMode == .auto ? nil : (appState.appearanceMode == .dark ? .dark : .light)
        )
        .environment(\.sparklePalette, palette)
        .background(
            SparkleWindowConfigurator(palette: palette, allowFullScreen: true) { [weak appState] window in
                appState?.hostWindow = window
            }
        )
        .onChange(of: systemColorScheme) { _ in
            appState.refreshActivePalette(emitChange: true)
            appState.applyAppearanceToApplication()
        }
        .onChange(of: palette.id) { _ in
            appState.applyAppearanceToApplication()
        }
        .onReceive(NotificationCenter.default.publisher(for: .sparkleConnectionsDidChange)) { notification in
            if (notification.object as? UUID) != appState.windowInstanceID {
                Task { await appState.refreshProfilesAndGroups() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .sparklePreferencesDidChange)) { notification in
            if (notification.object as? UUID) != appState.windowInstanceID {
                appState.reloadPreferencesFromNotification()
            }
        }
        .onReceive(appState.transferMonitor.$snapshots) { snapshots in
            appState.handleTransferSnapshotsChanged(snapshots)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if appState.isQuickConnectAvailable {
                    Button {
                        if let profile = appState.primarySelectedProfile {
                            Task { await appState.connect(profile: profile) }
                        }
                    } label: {
                        Label(appState.strings.connect, systemImage: SparkleTheme.Symbols.connect)
                    }
                    .disabled(appState.primarySelectedProfile == nil)
                } else if let current = appState.currentSession {
                    Button {
                        Task { await appState.disconnect(sessionID: current.id) }
                    } label: {
                        Label(appState.strings.disconnect, systemImage: SparkleTheme.Symbols.disconnect)
                    }
                }

                Button {
                    appState.openInternalEditorWindow()
                } label: {
                    Label(appState.strings.t("nav.editor"), systemImage: SparkleTheme.Symbols.editor)
                }
                .help(appState.strings.t("nav.editor"))

                Button {
                    Task { await appState.toggleTerminalDrawerForActiveTab() }
                } label: {
                    Label(appState.strings.terminal, systemImage: SparkleTheme.Symbols.terminal)
                }
                .disabled(appState.currentSession?.sshClient == nil && !appState.isTerminalVisible)

                Button {
                    appState.isShowingSyncSheet = true
                } label: {
                    Label(appState.strings.synchronize, systemImage: SparkleTheme.Symbols.sync)
                }
                .disabled(appState.currentSession == nil || !appState.featureFlags.isSyncEnabled)
                .accessibilityLabel(appState.strings.synchronize)

                Button {
                    isShowingSecurityDiagnostics = true
                } label: {
                    Label(appState.strings.securityDiagnostics, systemImage: SparkleTheme.Symbols.sftp)
                }
                .accessibilityLabel(appState.strings.securityDiagnostics)

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

                languageMenuSelector
                    .help(appState.strings.t("nav.switchLanguage"))

                Button {
                    appState.openAboutWindow()
                } label: {
                    Label(appState.strings.t("nav.about"), systemImage: "info.circle")
                }
                .help(appState.strings.t("nav.about"))
            }
        }
        .task {
            await appState.bootstrap()
        }
        .sheet(item: $editorMode) { mode in
            switch mode {
            case .create:
                ConnectionEditorView(appState: appState, existingProfile: nil)
                    .id(mode.id)
            case let .edit(profile):
                ConnectionEditorView(appState: appState, existingProfile: profile)
                    .id(mode.id)
            }
        }
        .sheet(isPresented: $appState.isShowingImportSheet) {
            ImportConnectionsSheet(appState: appState)
        }
        .sheet(isPresented: $isShowingSecurityDiagnostics) {
            SecurityDiagnosticsView(appState: appState)
        }
        .sheet(isPresented: $appState.isShowingSyncSheet) {
            SyncPreviewSheet(appState: appState)
        }
        .sheet(item: $appState.pendingHostChallenge) { challenge in
            HostKeyVerificationSheet(appState: appState, challenge: challenge)
        }
        .sheet(item: $appState.pendingCredentialPrompt) { req in
            CredentialPromptSheet(appState: appState, request: req)
        }
        .sheet(item: $appState.pendingConflict) { conflict in
            ConflictResolutionSheet(appState: appState, conflict: conflict)
        }
        .alert(
            appState.strings.hostKeyMismatchTitle,
            isPresented: Binding(
                get: { appState.hostMismatchAlert != nil },
                set: {
                    if !$0 {
                        appState.hostMismatchAlert = nil
                    }
                }
            )
        ) {
            Button(appState.strings.t("common.ok"), role: .cancel) { appState.hostMismatchAlert = nil }
        } message: {
            Text(appState.hostMismatchAlert?.errorDescription ?? "")
        }
        .alert(
            appState.strings.t("common.error"),
            isPresented: Binding(
                get: { appState.lastError != nil },
                set: {
                    if !$0 {
                        appState.lastError = nil
                    }
                }
            )
        ) {
            Button(appState.strings.t("common.ok"), role: .cancel) { appState.lastError = nil }
        } message: {
            Text(appState.lastError?.errorDescription ?? "")
        }
    }
}

private extension MainWindowView {
    var statusBar: some View {
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

            Toggle(appState.strings.t("nav.transfers"), isOn: $appState.isTransferDrawerVisible)
                .toggleStyle(.button)
                .controlSize(.small)
                .fixedSize()

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

    private var groupedThemeFamilies: [String] {
        var families: [String] = []
        for theme in appState.availableThemes where !families.contains(theme.family) {
            families.append(theme.family)
        }
        return families
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
