import SparkleDesignSystem
import SparkleTerminal
import SwiftUI

/// Dedicated iTerm2-style macOS standalone terminal window with tabs, vertical/horizontal split panes,
/// search bar (`⌘F`), font zoom (`⌘+`/`⌘-`/`⌘0`), and local login shell or active SSH execution.
struct StandaloneTerminalWindowView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var manager: StandaloneTerminalManager

    var body: some View {
        let palette = appState.activePalette
        let strings = appState.strings
        VStack(spacing: 0) {
            topActionBar(palette: palette, strings: strings)
            Divider()
            StandaloneTerminalTabStrip(manager: manager, palette: palette, strings: strings)
            Divider()
            if manager.isSearchVisible {
                StandaloneTerminalSearchBar(manager: manager, palette: palette, strings: strings)
                Divider()
            }
            mainTerminalBody(palette: palette, strings: strings)
            Divider()
            statusFooterBar(palette: palette, strings: strings)
        }
        .background(palette.canvasColor)
        .tint(palette.accentColor)
        .onAppear {
            manager.ensureInitialTab(workingDirectory: appState.localCurrentURL)
            manager.applyThemeColors(appState.terminalThemeColors)
        }
        .onChange(of: appState.activePalette) { _ in
            manager.applyThemeColors(appState.terminalThemeColors)
        }
    }

    private func topActionBar(palette: SparkleThemePalette, strings: AppStrings) -> some View {
        HStack(spacing: 8) {
            shellLaunchMenu(strings: strings)
            Button {
                _ = manager.splitFocusedPane(axis: .verticalDivider)
            } label: {
                Label(strings.t("terminal.standalone.splitVertical"), systemImage: "rectangle.split.2x1")
            }
            .buttonStyle(.bordered)
            .keyboardShortcut("d", modifiers: .command)
            .disabled(manager.activeTab == nil)

            Button {
                _ = manager.splitFocusedPane(axis: .horizontalDivider)
            } label: {
                Label(strings.t("terminal.standalone.splitHorizontal"), systemImage: "rectangle.split.1x2")
            }
            .buttonStyle(.bordered)
            .keyboardShortcut("d", modifiers: [.command, .shift])
            .disabled(manager.activeTab == nil)

            Spacer()

            Button {
                manager.toggleSearchBar()
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.bordered)
            .keyboardShortcut("f", modifiers: .command)
            .help(strings.t("terminal.standalone.find"))

            fontZoomControls(palette: palette, strings: strings)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(palette.windowColor)
    }

    private func shellLaunchMenu(strings: AppStrings) -> some View {
        Menu {
            Button(strings.t("terminal.standalone.newDefaultTab")) {
                _ = manager.openLocalTab(kind: .userDefault, workingDirectory: appState.localCurrentURL)
            }
            Button(strings.t("terminal.standalone.newBashTab")) {
                _ = manager.openLocalTab(kind: .bash, workingDirectory: appState.localCurrentURL)
            }
            Button(strings.t("terminal.standalone.newZshTab")) {
                _ = manager.openLocalTab(kind: .zsh, workingDirectory: appState.localCurrentURL)
            }
            if let session = appState.currentSession {
                Divider()
                Button("\(strings.t("terminal.standalone.newSSHTab")): \(session.profile.name)") {
                    do {
                        _ = try manager.openSSHTab(for: session.profile)
                    } catch {
                        appState.reportNonCancellationError(error)
                    }
                }
            }
        } label: {
            Label(strings.t("terminal.standalone.newTab"), systemImage: "plus.rectangle.on.rectangle")
        } primaryAction: {
            _ = manager.openLocalTab(kind: .userDefault, workingDirectory: appState.localCurrentURL)
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut("t", modifiers: .command)
    }

    private func fontZoomControls(palette: SparkleThemePalette, strings: AppStrings) -> some View {
        HStack(spacing: 4) {
            Button {
                manager.decreaseFontSize()
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .buttonStyle(.bordered)
            .keyboardShortcut("-", modifiers: .command)
            .help(strings.t("editor.zoomOut"))

            Button("\(Int(manager.fontSize))pt") {
                manager.resetFontSize()
            }
            .buttonStyle(.bordered)
            .keyboardShortcut("0", modifiers: .command)
            .foregroundStyle(palette.primaryTextColor)
            .help(strings.t("editor.zoomReset"))

            Button {
                manager.increaseFontSize()
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .buttonStyle(.bordered)
            .keyboardShortcut("=", modifiers: .command)
            .help(strings.t("editor.zoomIn"))
        }
    }

    @ViewBuilder
    private func mainTerminalBody(palette: SparkleThemePalette, strings: AppStrings) -> some View {
        if let activeTab = manager.activeTab {
            StandaloneTerminalSplitView(
                node: activeTab.rootNode,
                focusedPaneID: activeTab.focusedPaneID,
                totalPanes: activeTab.rootNode.paneIDs.count,
                manager: manager,
                palette: palette,
                strings: strings,
                terminalColors: appState.terminalThemeColors
            )
            .id(activeTab.id)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 10) {
                Text(strings.t("terminal.standalone.empty"))
                    .foregroundStyle(palette.secondaryTextColor)
                Button(strings.t("terminal.standalone.newTab")) {
                    _ = manager.openLocalTab(kind: .userDefault, workingDirectory: appState.localCurrentURL)
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func statusFooterBar(palette: SparkleThemePalette, strings: AppStrings) -> some View {
        HStack(spacing: 12) {
            if let pane = manager.focusedPane {
                Label(pane.launchConfig.executable, systemImage: "terminal.fill")
                    .font(SparkleTheme.Typography.monoSmall)
                    .foregroundStyle(palette.secondaryTextColor)
                Text(pane.currentDirectory)
                    .font(SparkleTheme.Typography.monoSmall)
                    .foregroundStyle(palette.secondaryTextColor)
                    .lineLimit(1)
                    .truncationMode(.head)
                Text(
                    pane.hasExited
                        ? strings.t("terminal.standalone.exited")
                        : strings.t("terminal.standalone.running")
                )
                .font(.caption2)
                .foregroundStyle(pane.hasExited ? SparkleTheme.Colors.warning : SparkleTheme.Colors.success)
            }
            Spacer()
            if let tab = manager.activeTab {
                Text("\(tab.rootNode.paneIDs.count) \(strings.t("terminal.standalone.panes"))")
                    .font(SparkleTheme.Typography.caption)
                    .foregroundStyle(palette.secondaryTextColor)
            }
            Text(appState.activePalette.displayName)
                .font(SparkleTheme.Typography.caption)
                .foregroundStyle(palette.secondaryTextColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(palette.windowColor)
    }
}
