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

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: SparkleTheme.Spacing.small) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(terminalManager.sessions) { session in
                            HStack(spacing: 6) {
                                Text(session.title)
                                    .font(SparkleTheme.Typography.caption)
                                Button {
                                    terminalManager.closeSession(id: session.id)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.caption2)
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                terminalManager.selectedSessionID == session.id
                                    ? appState.activePalette.accentColor.opacity(0.22)
                                    : appState.activePalette.canvasColor
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .onTapGesture {
                                terminalManager.selectedSessionID = session.id
                            }
                        }
                    }
                }

                Spacer()

                Button {
                    Task { await appState.openTerminalTab() }
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(appState.currentSession?.sshClient == nil)
                .help(appState.strings.t("nav.openTerminalTab"))

                Toggle(appState.strings.t("nav.split"), isOn: $appState.splitTerminalMode)
                    .toggleStyle(.button)

                Button(appState.strings.t("nav.snippets")) { isShowingSnippets = true }
                Button(appState.strings.t("nav.tunnels")) { isShowingForwarding = true }
            }
            .padding(.horizontal, SparkleTheme.Spacing.small)
            .padding(.vertical, SparkleTheme.Spacing.tiny)
            .background(appState.activePalette.windowColor)

            if terminalManager.sessions.isEmpty {
                VStack(spacing: SparkleTheme.Spacing.tiny) {
                    Text(appState.strings.t("nav.noActivePTY"))
                        .font(SparkleTheme.Typography.body)
                        .foregroundStyle(appState.activePalette.secondaryTextColor)
                    if appState.currentSession?.sshClient != nil {
                        Button(appState.strings.t("nav.openPTYShell")) {
                            Task { await appState.openTerminalTab() }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(appState.activePalette.canvasColor)
            } else if appState.splitTerminalMode, terminalManager.sessions.count >= 2 {
                let palette = appState.activePalette
                let termTheme = TerminalThemeColors(
                    backgroundHex: palette.canvasHex,
                    foregroundHex: palette.primaryTextHex,
                    caretHex: palette.accentHex,
                    selectionHex: palette.accentHex
                )
                HSplitView {
                    TerminalViewRepresentable(session: terminalManager.sessions[0], themeColors: termTheme)
                    TerminalViewRepresentable(session: terminalManager.sessions[1], themeColors: termTheme)
                }
            } else if let selected = terminalManager.sessions.first(where: {
                $0.id == terminalManager.selectedSessionID
            }) ?? terminalManager.sessions.last {
                let palette = appState.activePalette
                TerminalViewRepresentable(
                    session: selected,
                    themeColors: TerminalThemeColors(
                        backgroundHex: palette.canvasHex,
                        foregroundHex: palette.primaryTextHex,
                        caretHex: palette.accentHex,
                        selectionHex: palette.accentHex
                    )
                )
            }
        }
        .sheet(isPresented: $isShowingSnippets) {
            SnippetsSheet(appState: appState)
        }
        .sheet(isPresented: $isShowingForwarding) {
            PortForwardingSheet(appState: appState)
        }
        .sparkleWorkspaceSurface(appState.activePalette, useCanvas: true)
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
                        let active = appState.terminalManager.sessions.first {
                            $0.id == appState.terminalManager.selectedSessionID
                        }
                        active?.sendCommand(snippet.command)
                        dismiss()
                    }
                    .disabled(appState.terminalManager.sessions.isEmpty)
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
