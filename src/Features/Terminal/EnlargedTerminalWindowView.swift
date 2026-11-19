import SparkleCore
import SparkleDesignSystem
import SparkleNetworking
import SparkleTerminal
import SwiftUI

/// Dedicated enlarged macOS internal terminal window (matching external terminal size 1020x660 pt)
/// hosting the authenticated Swift-NIO-SSH interactive shell without requiring password input.
struct EnlargedTerminalWindowView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var terminalManager: TerminalSessionManager
    @State var isShowingSnippets = false
    @State var isShowingForwarding = false
    @State var isShowingFind = false
    @State var findQuery = ""
    @State var findSummary = ""
    @State var fontSize: CGFloat = 13.0

    init(appState: AppState) {
        self.appState = appState
        self.terminalManager = appState.terminalManager
    }

    var activeSession: TerminalTabSession? {
        if let selID = terminalManager.selectedSessionID,
           let found = terminalManager.sessions.first(where: { $0.id == selID }) {
            return found
        }
        return terminalManager.session(forWorkspaceTabID: appState.activeTabID) ?? terminalManager.sessions.first
    }

    var body: some View {
        let palette = appState.activePalette
        let strings = appState.strings
        VStack(spacing: 0) {
            topBar(palette: palette, strings: strings)
            Divider()
            if terminalManager.sessions.count > 1 {
                tabBar(palette: palette, strings: strings)
                Divider()
            }
            if isShowingFind {
                searchBar(palette: palette, strings: strings)
                Divider()
            }
            mainBody(palette: palette, strings: strings)
            Divider()
            footerBar(palette: palette, strings: strings)
        }
        .background(palette.canvasColor)
        .tint(palette.accentColor)
        .sheet(isPresented: $isShowingSnippets) {
            SnippetsSheet(appState: appState)
        }
        .sheet(isPresented: $isShowingForwarding) {
            PortForwardingSheet(appState: appState)
        }
    }
}

// MARK: - Subviews & Layout Extensions

extension EnlargedTerminalWindowView {
    func topBar(palette: SparkleThemePalette, strings: AppStrings) -> some View {
        HStack(spacing: 8) {
            topBarConnectionStatus(palette: palette, strings: strings)
            Spacer()
            topBarActionButtons(palette: palette, strings: strings)
            topBarZoomControls()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(palette.windowColor)
    }

    @ViewBuilder
    private func topBarConnectionStatus(palette: SparkleThemePalette, strings: AppStrings) -> some View {
        if let session = appState.currentSession {
            HStack(spacing: 6) {
                Circle()
                    .fill(SparkleTheme.Colors.success)
                    .frame(width: 8, height: 8)
                Text("\(session.profile.username)@\(session.profile.host):\(session.profile.port)")
                    .font(SparkleTheme.Typography.headline)
                    .foregroundStyle(palette.primaryTextColor)
                Text("(\(strings.t("term.connectedSSH")))")
                    .font(SparkleTheme.Typography.caption)
                    .foregroundStyle(SparkleTheme.Colors.success)
            }
        } else {
            HStack(spacing: 6) {
                Circle()
                    .fill(palette.secondaryTextColor)
                    .frame(width: 8, height: 8)
                Text(strings.t("term.disconnectedSSH"))
                    .font(SparkleTheme.Typography.headline)
                    .foregroundStyle(palette.secondaryTextColor)
            }
        }
    }

    @ViewBuilder
    private func topBarActionButtons(palette: SparkleThemePalette, strings: AppStrings) -> some View {
        if let sshClient = appState.currentSession?.sshClient {
            Button {
                Task {
                    do {
                        let count = terminalManager.sessions.count + 1
                        let name = "\(appState.currentSession?.profile.name ?? "SSH") (\(count))"
                        _ = try await terminalManager.openSession(
                            title: name,
                            workspaceTabID: appState.activeTabID,
                            remoteSessionID: appState.currentSession?.id,
                            sshClient: sshClient
                        )
                    } catch {
                        appState.reportNonCancellationError(error)
                    }
                }
            } label: {
                Label(strings.t("term.newSSHTab"), systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .help(strings.t("term.newSSHTab"))
        }

        Button {
            isShowingSnippets = true
        } label: {
            Label(strings.t("nav.snippets"), systemImage: "text.quote")
        }
        .buttonStyle(.bordered)
        .help(strings.t("nav.snippets"))

        if appState.featureFlags.isPortForwardingEnabled {
            Button {
                isShowingForwarding = true
            } label: {
                Label(strings.t("nav.tunnels"), systemImage: SparkleTheme.Symbols.tunnel)
            }
            .buttonStyle(.bordered)
            .help(strings.t("nav.tunnels"))
        }

        Button {
            isShowingFind.toggle()
        } label: {
            Image(systemName: "magnifyingglass")
        }
        .buttonStyle(.bordered)
        .keyboardShortcut("f", modifiers: .command)
        .help(strings.t("term.find"))
    }

    private func topBarZoomControls() -> some View {
        HStack(spacing: 2) {
            Button {
                fontSize = max(9.0, fontSize - 1.0)
                activeSession?.setFontSize(fontSize)
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .buttonStyle(.bordered)
            .keyboardShortcut("-", modifiers: .command)

            Button("\(Int(fontSize))pt") {
                fontSize = 13.0
                activeSession?.setFontSize(13.0)
            }
            .buttonStyle(.bordered)
            .keyboardShortcut("0", modifiers: .command)

            Button {
                fontSize = min(28.0, fontSize + 1.0)
                activeSession?.setFontSize(fontSize)
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .buttonStyle(.bordered)
            .keyboardShortcut("=", modifiers: .command)
        }
    }

    func tabBar(palette: SparkleThemePalette, strings: AppStrings) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(terminalManager.sessions) { sess in
                    let isSelected = (sess.id == (terminalManager.selectedSessionID ?? activeSession?.id))
                    tabChip(sess: sess, isSelected: isSelected, palette: palette)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .background(palette.windowColor.opacity(0.8))
    }

    private func tabChip(sess: TerminalTabSession, isSelected: Bool, palette: SparkleThemePalette) -> some View {
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
                        .font(.system(size: 9, weight: .bold))
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(isSelected ? palette.canvasColor : palette.windowColor)
        .cornerRadius(5)
        .contentShape(Rectangle())
        .onTapGesture {
            terminalManager.selectedSessionID = sess.id
        }
    }

    func searchBar(palette: SparkleThemePalette, strings: AppStrings) -> some View {
        HStack(spacing: SparkleTheme.Spacing.tiny) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(palette.secondaryTextColor)
            TextField(strings.t("term.findPlaceholder"), text: $findQuery)
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

            Button {
                performFind(forward: true)
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)

            Button {
                isShowingFind = false
                findQuery = ""
                findSummary = ""
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(palette.windowColor.opacity(0.95))
    }

    @ViewBuilder
    func mainBody(palette: SparkleThemePalette, strings: AppStrings) -> some View {
        if let session = activeSession {
            let termTheme = TerminalThemeColors(
                backgroundHex: palette.canvasHex,
                foregroundHex: palette.primaryTextHex,
                caretHex: palette.accentHex,
                selectionHex: palette.accentHex
            )
            TerminalViewRepresentable(session: session, themeColors: termTheme, fontSize: fontSize)
                .id(session.id)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 12) {
                Image(systemName: SparkleTheme.Symbols.terminal)
                    .font(.system(size: 40))
                    .foregroundStyle(palette.secondaryTextColor)
                Text(strings.t("nav.noActivePTY"))
                    .font(SparkleTheme.Typography.headline)
                    .foregroundStyle(palette.secondaryTextColor)
                if appState.currentSession?.sshClient != nil {
                    Button(strings.t("nav.openPTYShell")) {
                        Task { await appState.openTerminalTab() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(palette.canvasColor)
        }
    }

    func footerBar(palette: SparkleThemePalette, strings: AppStrings) -> some View {
        HStack(spacing: 12) {
            if let session = activeSession {
                Label(session.title, systemImage: "terminal.fill")
                    .font(SparkleTheme.Typography.monoSmall)
                    .foregroundStyle(palette.secondaryTextColor)
                if let dir = session.currentDirectory {
                    Text(dir)
                        .font(SparkleTheme.Typography.monoSmall)
                        .foregroundStyle(palette.secondaryTextColor)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                let statusText = session.isActive
                    ? strings.t("terminal.standalone.running")
                    : strings.t("terminal.standalone.exited")
                Text(statusText)
                    .font(.caption2)
                    .foregroundStyle(session.isActive ? SparkleTheme.Colors.success : SparkleTheme.Colors.warning)
            }
            Spacer()
            Text("\(terminalManager.sessions.count) \(strings.t("terminal.standalone.panes"))")
                .font(SparkleTheme.Typography.caption)
                .foregroundStyle(palette.secondaryTextColor)
            Text(appState.activePalette.displayName)
                .font(SparkleTheme.Typography.caption)
                .foregroundStyle(palette.secondaryTextColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(palette.windowColor)
    }

    private func performFind(forward: Bool) {
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
