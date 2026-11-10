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
        self.terminalManager = appState.terminalManager
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
                                    ? SparkleTheme.Colors.accent.opacity(0.2)
                                    : SparkleTheme.Colors.panelBackground
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
                .help("New Terminal Tab")

                Toggle("Split", isOn: $appState.splitTerminalMode)
                    .toggleStyle(.button)

                Button("Snippets") { isShowingSnippets = true }
                Button("Tunnels") { isShowingForwarding = true }
            }
            .padding(.horizontal, SparkleTheme.Spacing.small)
            .padding(.vertical, SparkleTheme.Spacing.tiny)
            .background(SparkleTheme.Colors.panelBackground)

            if terminalManager.sessions.isEmpty {
                VStack(spacing: SparkleTheme.Spacing.tiny) {
                    Text("No active SSH PTY sessions")
                        .font(SparkleTheme.Typography.body)
                        .foregroundStyle(SparkleTheme.Colors.secondaryText)
                    if appState.currentSession?.sshClient != nil {
                        Button("Open PTY Shell") {
                            Task { await appState.openTerminalTab() }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if appState.splitTerminalMode && terminalManager.sessions.count >= 2 {
                HSplitView {
                    TerminalViewRepresentable(session: terminalManager.sessions[0])
                    TerminalViewRepresentable(session: terminalManager.sessions[1])
                }
            } else if let selected = terminalManager.sessions.first(where: {
                $0.id == terminalManager.selectedSessionID
            }) ?? terminalManager.sessions.last {
                TerminalViewRepresentable(session: selected)
            }
        }
        .sheet(isPresented: $isShowingSnippets) {
            SnippetsSheet(appState: appState)
        }
        .sheet(isPresented: $isShowingForwarding) {
            PortForwardingSheet(appState: appState)
        }
    }
}

public struct SnippetsSheet: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SparkleTheme.Spacing.medium) {
            HStack {
                Text("Command Snippets").font(SparkleTheme.Typography.title)
                Spacer()
                Button("Close") { dismiss() }
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
                }
            }
        }
        .padding()
        .frame(width: 480, height: 360)
    }
}

public struct PortForwardingSheet: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var name = "Local Forward"
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
                TextField("Name", text: $name)
                TextField("Local Port", text: $bindPort).frame(width: 80)
                TextField("Remote Host", text: $targetHost)
                TextField("Remote Port", text: $targetPort).frame(width: 80)
                Button("Start") {
                    let rule = PortForwardingRule(
                        name: name,
                        direction: .local,
                        bindHost: "127.0.0.1",
                        bindPort: Int(bindPort) ?? 15_432,
                        targetHost: targetHost,
                        targetPort: Int(targetPort) ?? 5_432
                    )
                    Task { await appState.startPortForwarding(rule) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.currentSession?.sshClient == nil)
            }

            List(appState.activeTunnels) { tunnel in
                HStack {
                    let forwardSummary = "\(tunnel.rule.name): "
                        + "127.0.0.1:\(tunnel.listeningPort) -> "
                        + "\(tunnel.rule.targetHost):\(tunnel.rule.targetPort)"
                    Text(forwardSummary)
                        .font(SparkleTheme.Typography.monoSmall)
                    Spacer()
                    Button("Stop") {
                        Task { await appState.stopPortForwarding(id: tunnel.id) }
                    }
                }
            }
        }
        .padding()
        .frame(width: 600, height: 340)
    }
}
