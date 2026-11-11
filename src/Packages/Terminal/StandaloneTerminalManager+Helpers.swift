import AppKit
import SparkleCore
import SwiftTerm

extension StandaloneTerminalManager {
    func updatePaneTitle(_ title: String, for paneID: UUID) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var pane = panes[paneID] else { return }
        pane.title = trimmed
        panes[paneID] = pane
        if let tabIdx = tabs.firstIndex(where: { $0.rootNode.contains(paneID: paneID) }),
           tabs[tabIdx].focusedPaneID == paneID {
            tabs[tabIdx].title = trimmed
        }
    }

    func updatePaneDirectory(_ directory: String?, for paneID: UUID) {
        guard let directory, !directory.isEmpty, var pane = panes[paneID] else { return }
        if let url = URL(string: directory), url.isFileURL {
            pane.currentDirectory = url.path
        } else {
            pane.currentDirectory = directory
        }
        panes[paneID] = pane
    }

    func markPaneTerminated(paneID: UUID, exitCode: Int32?) {
        guard var pane = panes[paneID] else { return }
        pane.hasExited = true
        pane.exitCode = exitCode
        panes[paneID] = pane
    }

    func refreshTabTitle(at tabIdx: Int) {
        guard tabs.indices.contains(tabIdx) else { return }
        let focused = tabs[tabIdx].focusedPaneID
        tabs[tabIdx].title = panes[focused]?.title ?? tabs[tabIdx].title
    }

    func createTab(with config: StandaloneShellLaunchConfig) -> StandaloneTerminalTab {
        let pane = StandaloneTerminalPane(
            title: config.displayTitle,
            currentDirectory: config.initialDirectory,
            launchConfig: config
        )
        panes[pane.id] = pane
        let tab = StandaloneTerminalTab(
            title: config.displayTitle,
            rootNode: .pane(pane.id),
            focusedPaneID: pane.id
        )
        tabs.append(tab)
        selectedTabID = tab.id
        return tab
    }

    func resolveDirectoryPath(_ requested: URL?) -> String {
        if let requested, FileManager.default.fileExists(atPath: requested.path) {
            return requested.path
        }
        return FileManager.default.homeDirectoryForCurrentUser.path
    }

    func tearDownPaneView(id paneID: UUID) {
        if let view = liveViews.removeValue(forKey: paneID) {
            view.processDelegate = nil
            view.terminate()
            view.removeFromSuperview()
        }
        launchedPaneIDs.remove(paneID)
    }

    func applyFontSize(_ size: CGFloat) {
        fontSize = size
        let updatedFont = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        for view in liveViews.values {
            view.font = updatedFont
        }
    }

    func performSearch(forward: Bool) {
        guard let focusedID = activeTab?.focusedPaneID,
              let view = liveViews[focusedID]
        else { return }
        let query = searchQuery
        guard !query.isEmpty else {
            clearSearch()
            return
        }
        let options = SearchOptions(
            caseSensitive: searchCaseSensitive,
            regex: searchRegex,
            wholeWord: searchWholeWord
        )
        _ = forward
            ? view.findNext(query, options: options, scrollToResult: true)
            : view.findPrevious(query, options: options, scrollToResult: true)
        let summary = view.searchMatchSummary(query, options: options, limit: 1000)
        if summary.total > 0 {
            searchMatchSummaryText = "\(summary.index + 1)/\(summary.total)"
        } else {
            searchMatchSummaryText = "0/0"
        }
    }

    public nonisolated static func makeLocalLaunchConfig(
        kind: StandaloneShellKind,
        initialDirectory: String
    ) -> StandaloneShellLaunchConfig {
        let resolvedShell = resolveShellExecutable(for: kind)
        let title = URL(fileURLWithPath: resolvedShell).lastPathComponent
        return StandaloneShellLaunchConfig(
            executable: resolvedShell,
            args: ["-l"],
            initialDirectory: initialDirectory,
            displayTitle: title,
            kind: kind
        )
    }

    public nonisolated static func resolveShellExecutable(for kind: StandaloneShellKind) -> String {
        let fileManager = FileManager.default
        let candidates: [String]
        switch kind {
        case .bash:
            candidates = ["/usr/local/bin/bash", "/opt/homebrew/bin/bash", "/bin/bash"]
        case .zsh:
            candidates = ["/bin/zsh", "/usr/local/bin/zsh", "/bin/bash"]
        case .userDefault, .ssh:
            let envShell = ProcessInfo.processInfo.environment["SHELL"]
            let shellPrefix = envShell.map { [$0] } ?? []
            candidates = shellPrefix + ["/usr/local/bin/bash", "/bin/zsh", "/bin/bash"]
        }
        return candidates.first { fileManager.isExecutableFile(atPath: $0) } ?? "/bin/zsh"
    }
}
