import SparkleCore
import SparkleDesignSystem
import SparkleTerminal
import SwiftUI

public struct TerminalWorkspaceView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var terminalManager: TerminalSessionManager
    @State private var isShowingSnippets = false
    @State private var isShowingForwarding = false

    public init(appState: AppState) {
        self.appState = appState
        terminalManager = appState.terminalManager
    }

    private var boundShellSession: TerminalTabSession? {
        guard appState.currentSession != nil else { return nil }
        return terminalManager.session(forWorkspaceTabID: appState.activeTabID)
    }

    public var body: some View {
        let palette = appState.activePalette
        let shellSession = boundShellSession
        VStack(spacing: 0) {
            HStack(spacing: SparkleTheme.Spacing.small) {
                Label(
                    shellSession?
                        .title ?? (appState.currentSession?.profile.name ?? appState.strings.t("nav.terminal")),
                    systemImage: SparkleTheme.Symbols.terminal
                )
                .font(SparkleTheme.Typography.headline)
                .foregroundStyle(palette.primaryTextColor)

                Spacer()

                if appState.currentSession?.sshClient != nil, shellSession == nil || shellSession?.isActive == false {
                    Button {
                        Task { await appState.openTerminalTab() }
                    } label: {
                        Label(appState.strings.t("nav.openPTYShell"), systemImage: SparkleTheme.Symbols.terminal)
                    }
                    .help(appState.strings.t("nav.openTerminalTab"))
                }

                if let activeProfile = appState.currentSession?.profile ?? appState.primarySelectedProfile,
                   activeProfile.protocolType == .sftp || activeProfile.protocolType == .scp {
                    Button {
                        Task { await appState.openInExternalTerminal(activeProfile) }
                    } label: {
                        Image(systemName: "arrow.up.forward.app")
                    }
                    .help(appState.strings.t("nav.openInITerm"))
                }

                Button(appState.strings.t("nav.snippets")) { isShowingSnippets = true }
                Button(appState.strings.t("nav.tunnels")) { isShowingForwarding = true }

                Button {
                    appState.setActiveTabTerminalVisibility(false)
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help(appState.strings.t("nav.closeShell"))
            }
            .padding(.horizontal, SparkleTheme.Spacing.small)
            .padding(.vertical, SparkleTheme.Spacing.tiny)
            .background(palette.windowColor)

            if let activeShell = shellSession {
                let termTheme = TerminalThemeColors(
                    backgroundHex: palette.canvasHex,
                    foregroundHex: palette.primaryTextHex,
                    caretHex: palette.accentHex,
                    selectionHex: palette.accentHex
                )
                terminalSessionView(session: activeShell, themeColors: termTheme)
            } else {
                VStack(spacing: SparkleTheme.Spacing.tiny) {
                    Text(appState.strings.t("nav.noActivePTY"))
                        .font(SparkleTheme.Typography.body)
                        .foregroundStyle(palette.secondaryTextColor)
                    if appState.currentSession?.sshClient != nil {
                        Button {
                            Task { await appState.openTerminalTab() }
                        } label: {
                            Label(
                                appState.strings.t("nav.openPTYShell"),
                                systemImage: SparkleTheme.Symbols.terminal
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(palette.canvasColor)
            }
        }
        .sheet(isPresented: $isShowingSnippets) {
            SnippetsSheet(appState: appState)
        }
        .sheet(isPresented: $isShowingForwarding) {
            PortForwardingSheet(appState: appState)
        }
        .sparkleWorkspaceSurface(palette, useCanvas: true)
    }

    private func terminalSessionView(session: TerminalTabSession, themeColors: TerminalThemeColors) -> some View {
        TerminalViewRepresentable(session: session, themeColors: themeColors)
            .id(session.id)
    }
}

public struct SnippetsSheet: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var newTitle = ""
    @State private var newCommand = ""

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SparkleTheme.Spacing.medium) {
            HStack {
                Text(appState.strings.t("nav.snippets")).font(SparkleTheme.Typography.title)
                Spacer()
                Button(appState.strings.t("common.close")) { dismiss() }
            }

            HStack {
                TextField("Title", text: $newTitle)
                TextField("Command", text: $newCommand)
                Button(appState.strings.t("common.add")) {
                    let title = newTitle
                    let cmd = newCommand
                    newTitle = ""
                    newCommand = ""
                    Task { await appState.addSnippet(title: title, command: cmd) }
                }
                .disabled(newTitle.isEmpty || newCommand.isEmpty)
            }

            List(appState.snippets) { snippet in
                HStack {
                    VStack(alignment: .leading) {
                        Text(snippet.title).font(SparkleTheme.Typography.headline)
                        Text(snippet.command).font(SparkleTheme.Typography.monoSmall)
                    }
                    Spacer()
                    Button("Run") {
                        let active = appState.terminalManager.session(forWorkspaceTabID: appState.activeTabID)
                        active?.sendCommand(snippet.command)
                        dismiss()
                    }
                    .disabled(appState.terminalManager.session(forWorkspaceTabID: appState.activeTabID) == nil)
                    Button(role: .destructive) {
                        Task { await appState.deleteSnippet(id: snippet.id) }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
                .listRowBackground(appState.activePalette.canvasColor)
            }
            .scrollContentBackground(.hidden)
            .background(appState.activePalette.canvasColor)
        }
        .padding()
        .frame(width: 540, height: 400)
        .sparkleWorkspaceSurface(appState.activePalette)
    }
}

public struct PortForwardingSheet: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var name = "Tunnel Forward"
    @State private var direction: PortForwardingRule.Direction = .local
    @State private var bindPort = "15432"
    @State private var targetHost = "127.0.0.1"
    @State private var targetPort = "5432"

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SparkleTheme.Spacing.medium) {
            HStack {
                Label("SSH Port Forwarding", systemImage: SparkleTheme.Symbols.tunnel)
                    .font(SparkleTheme.Typography.title)
                Spacer()
                Button("Close") { dismiss() }
            }

            HStack {
                Picker("Mode", selection: $direction) {
                    Text("Local (-L)").tag(PortForwardingRule.Direction.local)
                    Text("Remote (-R)").tag(PortForwardingRule.Direction.remote)
                }
                .frame(width: 130)
                TextField("Name", text: $name)
                TextField("Bind Port", text: $bindPort).frame(width: 75)
                TextField("Target Host", text: $targetHost)
                TextField("Target Port", text: $targetPort).frame(width: 75)
                Button("Start") {
                    let rule = PortForwardingRule(
                        name: name,
                        direction: direction,
                        bindHost: "127.0.0.1",
                        bindPort: Int(bindPort) ?? 15432,
                        targetHost: targetHost,
                        targetPort: Int(targetPort) ?? 5432
                    )
                    Task { await appState.startPortForwarding(rule) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.currentSession?.sshClient == nil)
            }

            List(appState.activeTunnels) { tunnel in
                HStack {
                    let arrow = tunnel.rule.direction == .local ? "-L" : "-R"
                    let forwardSummary = "[\(arrow)] \(tunnel.rule.name): "
                        + "127.0.0.1:\(tunnel.listeningPort) -> "
                        + "\(tunnel.rule.targetHost):\(tunnel.rule.targetPort)"
                    Text(forwardSummary)
                        .font(SparkleTheme.Typography.monoSmall)
                    Spacer()
                    Button("Stop") {
                        Task { await appState.stopPortForwarding(id: tunnel.id) }
                    }
                }
                .listRowBackground(appState.activePalette.canvasColor)
            }
            .scrollContentBackground(.hidden)
            .background(appState.activePalette.canvasColor)
        }
        .padding()
        .frame(width: 680, height: 360)
        .sparkleWorkspaceSurface(appState.activePalette)
    }
}
