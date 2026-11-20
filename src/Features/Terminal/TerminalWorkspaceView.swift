import SparkleCore
import SparkleDesignSystem
import SparkleTerminal
import SwiftUI

public struct TerminalWorkspaceView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var terminalManager: TerminalSessionManager
    @State private var isShowingSnippets = false
    @State private var isShowingForwarding = false
    @State private var isShowingFind = false
    @State private var findQuery = ""
    @State private var findSummary = ""

    public init(appState: AppState) {
        self.appState = appState
        terminalManager = appState.terminalManager
    }

    private var visibleSessions: [TerminalTabSession] {
        if let currentRemote = appState.currentSession?.id {
            return terminalManager.sessions.filter { $0.remoteSessionID == currentRemote }
        } else {
            return terminalManager.sessions.filter { $0.remoteSessionID == nil }
        }
    }

    private var activeSession: TerminalTabSession? {
        if let currentRemote = appState.currentSession?.id {
            if let selID = terminalManager.selectedSessionID,
               let found = terminalManager.sessions.first(where: {
                   $0.id == selID && $0.remoteSessionID == currentRemote && $0.isActive
               }) {
                return found
            }
            if let match = terminalManager.sessions.first(where: {
                $0.remoteSessionID == currentRemote && $0.isActive
            }) {
                return match
            }
            return terminalManager.sessions.first(where: { $0.remoteSessionID == currentRemote })
        } else {
            if let selID = terminalManager.selectedSessionID,
               let found = terminalManager.sessions.first(where: {
                   $0.id == selID && $0.remoteSessionID == nil && $0.isActive
               }) {
                return found
            }
            return terminalManager.sessions.first(where: { $0.remoteSessionID == nil && $0.isActive })
                ?? terminalManager.sessions.first(where: { $0.remoteSessionID == nil })
        }
    }

    public var body: some View {
        let palette = appState.activePalette
        let shellSession = activeSession
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

                if appState.currentSession?.sshClient != nil {
                    Button {
                        Task { await appState.openTerminalTab() }
                    } label: {
                        Label(appState.strings.t("term.newSSHTab"), systemImage: "plus")
                    }
                    .help(appState.strings.t("term.newSSHTab"))
                }

                Button {
                    Task { await appState.openEnlargedTerminalWindow() }
                } label: {
                    Image(systemName: SparkleTheme.Symbols.enlargedTerminal)
                }
                .help(appState.strings.t("nav.enlargedTerminalTooltip"))

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
                if appState.featureFlags.isPortForwardingEnabled {
                    Button(appState.strings.t("nav.tunnels")) { isShowingForwarding = true }
                }

                Button {
                    isShowingFind.toggle()
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.borderless)
                .help(appState.strings.t("term.find"))

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

            tabBar(palette: palette)

            if isShowingFind {
                HStack(spacing: SparkleTheme.Spacing.tiny) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(palette.secondaryTextColor)
                    TextField(appState.strings.t("term.findPlaceholder"), text: $findQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .onSubmit { performFind(forward: true) }
                    if !findSummary.isEmpty {
                        Text(findSummary)
                            .font(.caption2)
                            .foregroundStyle(palette.secondaryTextColor)
                    }
                    Button {
                        performFind(forward: false)
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .buttonStyle(.borderless)
                    .help(appState.strings.t("editor.findPrev"))

                    Button {
                        performFind(forward: true)
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .buttonStyle(.borderless)
                    .help(appState.strings.t("editor.findNext"))

                    Button {
                        isShowingFind = false
                        findQuery = ""
                        findSummary = ""
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, SparkleTheme.Spacing.small)
                .padding(.vertical, 4)
                .background(palette.windowColor.opacity(0.95))
            }

            if appState.isTerminalEnlarged {
                VStack(spacing: SparkleTheme.Spacing.small) {
                    Image(systemName: SparkleTheme.Symbols.enlargedTerminal)
                        .font(.system(size: 28))
                        .foregroundStyle(palette.accentColor)
                    Text(appState.strings.t("term.enlargedTitle"))
                        .font(SparkleTheme.Typography.headline)
                        .foregroundStyle(palette.primaryTextColor)
                    Text(appState.strings.t("term.enlargedSubtitle"))
                        .font(SparkleTheme.Typography.caption)
                        .foregroundStyle(palette.secondaryTextColor)
                    HStack(spacing: 8) {
                        Button(appState.strings.t("term.bringToFront")) {
                            appState.enlargedTerminalWindowController.present(appState: appState)
                        }
                        .buttonStyle(.bordered)

                        Button(appState.strings.t("term.reattachDrawer")) {
                            appState.closeEnlargedTerminalWindow()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                if let view = activeSession?.getOrCreateTerminalView() {
                                    view.terminal.updateFullScreen()
                                    view.feed(text: "")
                                    view.setNeedsDisplay(view.bounds)
                                    view.window?.makeFirstResponder(view)
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(palette.canvasColor)
            } else if let activeShell = shellSession {
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
                .task {
                    if let session = appState.currentSession, let sshClient = session.sshClient {
                        _ = try? await terminalManager.openSession(
                            title: session.profile.name,
                            workspaceTabID: appState.activeTabID,
                            remoteSessionID: session.id,
                            sshClient: sshClient
                        )
                    }
                }
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
}

// MARK: - Subviews & Search Extensions
extension TerminalWorkspaceView {
    @ViewBuilder
    fileprivate func tabBar(palette: SparkleThemePalette) -> some View {
        let currentSessions = visibleSessions
        if currentSessions.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(currentSessions) { sess in
                        let isSelected = (sess.id == (terminalManager.selectedSessionID ?? activeSession?.id))
                        tabChip(sess: sess, isSelected: isSelected, palette: palette)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
            }
            .background(palette.windowColor.opacity(0.85))
            Divider()
        }
    }

    fileprivate func tabChip(
        sess: TerminalTabSession,
        isSelected: Bool,
        palette: SparkleThemePalette
    ) -> some View {
        Button {
            terminalManager.selectedSessionID = sess.id
            let view = sess.getOrCreateTerminalView()
            view.terminal.updateFullScreen()
            view.feed(text: "")
            view.setNeedsDisplay(view.bounds)
            view.window?.makeFirstResponder(view)
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(sess.isActive ? SparkleTheme.Colors.success : SparkleTheme.Colors.danger)
                    .frame(width: 6, height: 6)
                Text(sess.title)
                    .font(SparkleTheme.Typography.caption.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? palette.primaryTextColor : palette.secondaryTextColor)
                if terminalManager.sessions.count > 1 {
                    Button {
                        terminalManager.closeSession(id: sess.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(isSelected ? palette.canvasColor : palette.windowColor)
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }

    fileprivate func terminalSessionView(
        session: TerminalTabSession,
        themeColors: TerminalThemeColors
    ) -> some View {
        TerminalViewRepresentable(session: session, themeColors: themeColors)
            .id(session.id)
    }

    fileprivate func performFind(forward: Bool) {
        guard let session = activeSession, !findQuery.isEmpty else {
            findSummary = ""
            return
        }
        let res = forward ? session.searchNext(findQuery) : session.searchPrevious(findQuery)
        if let res, res.total > 0 {
            findSummary = "\(res.index + 1)/\(res.total)"
        } else {
            findSummary = "0/0"
        }
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
                    Text("Dynamic (-D)").tag(PortForwardingRule.Direction.dynamic)
                }
                .frame(width: 140)
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
