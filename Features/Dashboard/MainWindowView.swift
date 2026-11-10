import SparkleCore
import SparkleDesignSystem
import SwiftUI

public struct MainWindowView: View {
    @ObservedObject var appState: AppState
    @State private var isShowingEditor = false
    @State private var editingProfile: ConnectionProfile?
    @State private var isShowingSecurityDiagnostics = false
    @State private var isShowingSyncSheet = false

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        NavigationSplitView {
            ConnectionManagerView(
                appState: appState,
                isShowingEditor: $isShowingEditor,
                editingProfile: $editingProfile
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
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    if let selectedID = appState.selectedProfileID,
                       let profile = appState.profiles.first(where: { $0.id == selectedID }) {
                        Task { await appState.connect(profile: profile) }
                    }
                } label: {
                    Label(appState.strings.connect, systemImage: SparkleTheme.Symbols.connect)
                }
                .disabled(appState.selectedProfileID == nil)

                if let current = appState.currentSession {
                    Button {
                        Task { await appState.disconnect(sessionID: current.id) }
                    } label: {
                        Label(appState.strings.disconnect, systemImage: SparkleTheme.Symbols.disconnect)
                    }
                }

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
            }
        }
        .task {
            await appState.bootstrap()
        }
        .sheet(isPresented: $isShowingEditor) {
            ConnectionEditorView(appState: appState, existingProfile: editingProfile)
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
        .sheet(item: $appState.pendingConflict) { conflict in
            ConflictResolutionSheet(appState: appState, conflict: conflict)
        }
        .alert(
            appState.strings.hostKeyMismatchTitle,
            isPresented: Binding(
                get: { appState.hostMismatchAlert != nil },
                set: { if !$0 { appState.hostMismatchAlert = nil } }
            )
        ) {
            Button("OK", role: .cancel) { appState.hostMismatchAlert = nil }
        } message: {
            Text(appState.hostMismatchAlert?.errorDescription ?? "")
        }
        .alert(
            "Error",
            isPresented: Binding(
                get: { appState.lastError != nil },
                set: { if !$0 { appState.lastError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { appState.lastError = nil }
        } message: {
            Text(appState.lastError?.errorDescription ?? "")
        }
    }

    private var sessionTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
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
                            ? SparkleTheme.Colors.accent.opacity(0.2)
                            : SparkleTheme.Colors.panelBackground
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
        .background(.ultraThinMaterial)
    }

    private var statusBar: some View {
        HStack(spacing: SparkleTheme.Spacing.medium) {
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
                Text("Disconnected")
                    .font(SparkleTheme.Typography.caption)
                    .foregroundStyle(SparkleTheme.Colors.secondaryText)
            }

            if let message = appState.statusBannerMessage {
                Text("· \(message)")
                    .font(SparkleTheme.Typography.caption)
                    .foregroundStyle(SparkleTheme.Colors.secondaryText)
            }

            Spacer()

            Toggle("Terminal", isOn: $appState.isTerminalVisible)
                .toggleStyle(.button)
                .controlSize(.small)

            Toggle("Transfers", isOn: $appState.isTransferDrawerVisible)
                .toggleStyle(.button)
                .controlSize(.small)

            Button(appState.language == .english ? "EN" : "ID") {
                appState.language = appState.language == .english ? .indonesian : .english
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, SparkleTheme.Spacing.medium)
        .padding(.vertical, SparkleTheme.Spacing.tiny)
        .background(SparkleTheme.Colors.panelBackground)
    }
}
