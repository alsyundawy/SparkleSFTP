import SparkleCore
import SparkleDesignSystem
import SwiftUI

public struct MainWindowView: View {
    @ObservedObject var appState: AppState
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var editorMode: ConnectionEditorMode?
    @State private var isShowingSecurityDiagnostics = false
    @State private var isShowingSyncSheet = false

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
                if !appState.activeSessions.isEmpty {
                    sessionTabBar
                }

                VSplitView {
                    DualPaneCommanderView(appState: appState)
                        .frame(minHeight: 280)

                    if appState.isTerminalVisible {
                        TerminalWorkspaceView(appState: appState)
                            .frame(minHeight: 180)
                    }

                    if appState.isTransferDrawerVisible {
                        TransferQueueView(appState: appState)
                            .frame(minHeight: 120, idealHeight: 160)
                    }
                }

                statusBar
            }
            .background(palette.windowColor)
            .foregroundStyle(palette.primaryTextColor)
            .tint(palette.accentColor)
        }
        .preferredColorScheme(
            appState.appearanceMode == .auto ? nil : (appState.appearanceMode == .dark ? .dark : .light)
        )
        .environment(\.sparklePalette, palette)
        .onChange(of: systemColorScheme) { _ in
            appState.refreshActivePalette(emitChange: true)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    if let profile = appState.primarySelectedProfile {
                        Task { await appState.connect(profile: profile) }
                    }
                } label: {
                    Label(appState.strings.connect, systemImage: SparkleTheme.Symbols.connect)
                }
                .disabled(appState.primarySelectedProfile == nil)

                if let current = appState.currentSession {
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
                    Task { await appState.openTerminalTab() }
                } label: {
                    Label(appState.strings.terminal, systemImage: SparkleTheme.Symbols.terminal)
                }
                .disabled(appState.currentSession?.sshClient == nil)

                Button {
                    isShowingSyncSheet = true
                } label: {
                    Label(appState.strings.synchronize, systemImage: SparkleTheme.Symbols.sync)
                }
                .disabled(appState.currentSession == nil || !appState.featureFlags.isSyncEnabled)
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .accessibilityLabel(appState.strings.synchronize)

                Button {
                    isShowingSecurityDiagnostics = true
                } label: {
                    Label(appState.strings.securityDiagnostics, systemImage: SparkleTheme.Symbols.sftp)
                }
                .accessibilityLabel(appState.strings.securityDiagnostics)

                Menu {
                    ForEach(appState.availableThemes.prefix(16)) { theme in
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
                } label: {
                    Label(appState.strings.t("prefs.tabThemes"), systemImage: SparkleTheme.Symbols.theme)
                }
                .help(appState.activePalette.displayName)

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
        .sheet(isPresented: $isShowingSyncSheet) {
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
    var sessionTabBar: some View {
        let palette = appState.activePalette
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(appState.activeSessions) { session in
                    HStack(spacing: 6) {
                        Image(
                            systemName: session.profile.protocolType.isEncryptedByDefault
                                ? SparkleTheme.Symbols.sftp
                                : SparkleTheme.Symbols.ftpInsecure
                        )
                        Text(session.profile.name)
                            .font(SparkleTheme.Typography.caption)
                        Button {
                            Task { await appState.disconnect(sessionID: session.id) }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption2)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        appState.activeSessionID == session.id
                            ? palette.accentColor.opacity(0.22)
                            : palette.canvasColor
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .onTapGesture {
                        appState.activeSessionID = session.id
                    }
                }
            }
            .padding(.horizontal, SparkleTheme.Spacing.small)
            .padding(.vertical, 4)
        }
        .background(palette.windowColor)
    }

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
            } else {
                Text(appState.strings.t("nav.disconnected"))
                    .font(SparkleTheme.Typography.caption)
                    .foregroundStyle(palette.secondaryTextColor)
            }

            if let message = appState.statusBannerMessage {
                Text("· \(message)")
                    .font(SparkleTheme.Typography.caption)
                    .foregroundStyle(palette.secondaryTextColor)
            }

            Spacer()

            Text(palette.displayName)
                .font(SparkleTheme.Typography.caption)
                .foregroundStyle(palette.secondaryTextColor)

            Toggle(appState.strings.t("nav.terminal"), isOn: $appState.isTerminalVisible)
                .toggleStyle(.button)
                .controlSize(.small)

            Toggle(appState.strings.t("nav.transfers"), isOn: $appState.isTransferDrawerVisible)
                .toggleStyle(.button)
                .controlSize(.small)

            Menu(appState.activeLocaleCode.uppercased()) {
                ForEach(appState.availableLocales) { doc in
                    Button(doc.displayName) {
                        appState.selectLocale(code: doc.code)
                    }
                }
            }
            .controlSize(.small)
        }
        .padding(.horizontal, SparkleTheme.Spacing.medium)
        .padding(.vertical, SparkleTheme.Spacing.tiny)
        .background(palette.windowColor)
    }
}
