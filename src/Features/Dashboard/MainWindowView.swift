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
                    appState.openStandaloneTerminal()
                } label: {
                    Label(appState.strings.t("nav.standaloneTerminal"), systemImage: "macwindow.on.rectangle")
                }
                .help(appState.strings.t("nav.standaloneTerminal"))

                Button {
                    withAnimation {
                        appState.isActivityLogVisible.toggle()
                    }
                } label: {
                    Label(appState.strings.t("activityLog.title"), systemImage: "list.bullet.rectangle")
                }
                .help(appState.strings.t("activityLog.toggleTooltip"))

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
        .sheet(
            item: $appState.pendingHostChallenge,
            onDismiss: { appState.cancelPendingHostChallengeIfNeeded() },
            content: { challenge in
                HostKeyVerificationSheet(appState: appState, challenge: challenge)
            }
        )
        .sheet(
            item: $appState.pendingCredentialPrompt,
            onDismiss: { appState.cancelPendingCredentialPromptIfNeeded() },
            content: { req in
                CredentialPromptSheet(appState: appState, request: req)
            }
        )
        .sheet(
            item: $appState.pendingConflict,
            onDismiss: { appState.cancelPendingConflictIfNeeded() },
            content: { conflict in
                ConflictResolutionSheet(appState: appState, conflict: conflict)
            }
        )
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
