import AppKit
import Foundation
import SparkleCore
import SwiftTerm

/// Coordinator managing multi-tab, iTerm2-style split-pane standalone macOS terminal sessions
/// backed directly by `SwiftTerm.LocalProcessTerminalView`.
@MainActor
public final class StandaloneTerminalManager: ObservableObject {
    @Published public internal(set) var tabs: [StandaloneTerminalTab] = []
    @Published public var selectedTabID: UUID?
    @Published public internal(set) var panes: [UUID: StandaloneTerminalPane] = [:]
    @Published public var fontSize: CGFloat = 13.0
    @Published public var isSearchVisible = false
    @Published public var searchQuery = ""
    @Published public var searchCaseSensitive = false
    @Published public var searchRegex = false
    @Published public var searchWholeWord = false
    @Published public internal(set) var searchMatchSummaryText = ""

    var liveViews: [UUID: LocalProcessTerminalView] = [:]
    var launchedPaneIDs: Set<UUID> = []
    private var cachedThemeColors: TerminalThemeColors?

    public init() {}

    public var activeTab: StandaloneTerminalTab? {
        guard let selectedTabID else { return tabs.first }
        return tabs.first { $0.id == selectedTabID } ?? tabs.first
    }

    public var focusedPane: StandaloneTerminalPane? {
        guard let activeTab else { return nil }
        return panes[activeTab.focusedPaneID]
    }

    public func ensureInitialTab(workingDirectory: URL? = nil) {
        if tabs.isEmpty {
            _ = openLocalTab(kind: .userDefault, workingDirectory: workingDirectory)
        }
    }

    @discardableResult
    public func openLocalTab(
        kind: StandaloneShellKind = .userDefault,
        workingDirectory: URL? = nil
    ) -> StandaloneTerminalTab {
        let dirPath = resolveDirectoryPath(workingDirectory)
        let config = Self.makeLocalLaunchConfig(kind: kind, initialDirectory: dirPath)
        return createTab(with: config)
    }

    @discardableResult
    public func openSSHTab(
        for profile: ConnectionProfile,
        jumpProfile: ConnectionProfile? = nil
    ) throws -> StandaloneTerminalTab {
        let parts = try ExternalTerminalLauncher.buildOpenSSHCommandParts(
            for: profile,
            jumpProfile: jumpProfile
        )
        let executable = parts.first ?? "/usr/bin/ssh"
        let args = Array(parts.dropFirst())
        let label = "\(profile.username)@\(profile.host)"
        let config = StandaloneShellLaunchConfig(
            executable: executable,
            args: args,
            initialDirectory: FileManager.default.homeDirectoryForCurrentUser.path,
            displayTitle: label,
            kind: .ssh
        )
        return createTab(with: config)
    }

    @discardableResult
    public func splitFocusedPane(axis: TerminalSplitAxis) -> StandaloneTerminalPane? {
        guard let currentTabID = activeTab?.id,
              let tabIdx = tabs.firstIndex(where: { $0.id == currentTabID })
        else { return nil }
        let sourcePaneID = tabs[tabIdx].focusedPaneID
        let sourceDir = panes[sourcePaneID]?.currentDirectory ?? panes[sourcePaneID]?.launchConfig.initialDirectory
        let dirURL = sourceDir.map { URL(fileURLWithPath: $0) }
        let config = Self.makeLocalLaunchConfig(kind: .userDefault, initialDirectory: resolveDirectoryPath(dirURL))
        let newPane = StandaloneTerminalPane(
            title: config.displayTitle,
            currentDirectory: config.initialDirectory,
            launchConfig: config
        )
        panes[newPane.id] = newPane
        tabs[tabIdx].rootNode = tabs[tabIdx].rootNode.splitting(
            targetPaneID: sourcePaneID,
            axis: axis,
            newPaneID: newPane.id
        )
        tabs[tabIdx].focusedPaneID = newPane.id
        return newPane
    }

    public func focusPane(_ paneID: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.rootNode.contains(paneID: paneID) }) else { return }
        selectedTabID = tabs[idx].id
        tabs[idx].focusedPaneID = paneID
        if let view = liveViews[paneID], let window = view.window {
            window.makeFirstResponder(view)
        }
    }

    public func focusAdjacentPane(delta: Int) {
        guard let tabIdx = tabs.firstIndex(where: { $0.id == activeTab?.id }),
              let nextID = tabs[tabIdx].rootNode.adjacentPaneID(from: tabs[tabIdx].focusedPaneID, delta: delta)
        else { return }
        focusPane(nextID)
    }

    public func closePane(id paneID: UUID) {
        tearDownPaneView(id: paneID)
        panes.removeValue(forKey: paneID)
        guard let tabIdx = tabs.firstIndex(where: { $0.rootNode.contains(paneID: paneID) }) else { return }
        if let nextRoot = tabs[tabIdx].rootNode.removing(targetPaneID: paneID) {
            tabs[tabIdx].rootNode = nextRoot
            if tabs[tabIdx].focusedPaneID == paneID, let fallback = nextRoot.paneIDs.first {
                tabs[tabIdx].focusedPaneID = fallback
            }
            refreshTabTitle(at: tabIdx)
        } else {
            let removedTabID = tabs[tabIdx].id
            tabs.remove(at: tabIdx)
            if selectedTabID == removedTabID {
                selectedTabID = tabs.last?.id
            }
        }
    }

    public func closeTab(id tabID: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        for paneID in tabs[idx].rootNode.paneIDs {
            tearDownPaneView(id: paneID)
            panes.removeValue(forKey: paneID)
        }
        tabs.remove(at: idx)
        if selectedTabID == tabID {
            selectedTabID = tabs.last?.id
        }
    }

    public func terminateAll() {
        for paneID in Array(liveViews.keys) {
            tearDownPaneView(id: paneID)
        }
        panes.removeAll()
        tabs.removeAll()
        selectedTabID = nil
    }

    public func selectAdjacentTab(delta: Int) {
        guard tabs.count > 1,
              let activeID = activeTab?.id,
              let idx = tabs.firstIndex(where: { $0.id == activeID })
        else { return }
        let targetIdx = (idx + delta % tabs.count + tabs.count) % tabs.count
        selectedTabID = tabs[targetIdx].id
    }

    public func increaseFontSize() {
        applyFontSize(min(28.0, fontSize + 1.0))
    }

    public func decreaseFontSize() {
        applyFontSize(max(9.0, fontSize - 1.0))
    }

    public func resetFontSize() {
        fontSize = 13.0
        for view in liveViews.values {
            view.font = NSFont.monospacedSystemFont(ofSize: 13.0, weight: .regular)
        }
    }

    public func applyThemeColors(_ colors: TerminalThemeColors?) {
        cachedThemeColors = colors
        for view in liveViews.values {
            TerminalThemeColors.apply(colors, to: view)
        }
    }

    public func toggleSearchBar() {
        isSearchVisible.toggle()
        if !isSearchVisible {
            clearSearch()
        }
    }

    public func findNext() {
        performSearch(forward: true)
    }

    public func findPrevious() {
        performSearch(forward: false)
    }

    public func clearSearch() {
        searchMatchSummaryText = ""
        for view in liveViews.values {
            view.clearSearch()
        }
    }

    public func existingOrCreateView(
        for pane: StandaloneTerminalPane,
        colors: TerminalThemeColors?,
        delegate: any LocalProcessTerminalViewDelegate
    ) -> LocalProcessTerminalView {
        if let existing = liveViews[pane.id] {
            existing.processDelegate = delegate
            return existing
        }
        let options = TerminalOptions(
            termName: "xterm-256color",
            scrollback: 10000
        )
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let terminalView = LocalProcessTerminalView(frame: .zero, font: font, options: options)
        terminalView.processDelegate = delegate
        TerminalThemeColors.apply(colors ?? cachedThemeColors, to: terminalView)
        liveViews[pane.id] = terminalView
        if !launchedPaneIDs.contains(pane.id) {
            launchedPaneIDs.insert(pane.id)
            let execName = "-" + URL(fileURLWithPath: pane.launchConfig.executable).lastPathComponent
            terminalView.startProcess(
                executable: pane.launchConfig.executable,
                args: pane.launchConfig.args,
                environment: nil,
                execName: pane.launchConfig.kind == .ssh ? nil : execName,
                currentDirectory: pane.launchConfig.initialDirectory
            )
        }
        return terminalView
    }
}
