import AppKit
import Foundation
import SparkleCore

@MainActor
private enum TransferRefreshTracker {
    static var completedIDsByWindow: [UUID: Set<UUID>] = [:]
    static var debounceTasksByWindow: [UUID: Task<Void, Never>] = [:]
}

public extension AppState {
    func selectAdjacentWorkspaceTab(delta: Int) {
        guard workspaceTabs.count > 1,
              let currentIdx = workspaceTabs.firstIndex(where: { $0.id == activeTabID })
        else { return }
        let nextIdx = (currentIdx + delta + workspaceTabs.count) % workspaceTabs.count
        let targetID = workspaceTabs[nextIdx].id
        if let pendingURL = selectWorkspaceTabSync(id: targetID) {
            Task { await refreshLocalDirectory(pendingURL, recordHistory: false) }
        }
    }

    func promptCreateFolderShortcut() {
        if activePane == .right, currentSession == nil {
            activePane = .left
        }
        NotificationCenter.default.post(name: .sparkleRequestNewFolder, object: windowInstanceID)
    }

    func switchCommanderPaneWithFocus() {
        switchActivePane()
        let isLocal = activePane == .left
        if let window = NSApp?.keyWindow {
            NotificationCenter.default.post(
                name: .sparklePaneFocusRequested,
                object: window,
                userInfo: ["isLocal": isLocal]
            )
        }
    }

    func handleTransferSnapshotsChanged(_ snapshots: [TransferSnapshot]) {
        let completed = snapshots.filter { $0.status == .completed }
        guard !completed.isEmpty else { return }

        var known = TransferRefreshTracker.completedIDsByWindow[windowInstanceID] ?? []
        var sawNewLocalDownload = false
        var sawNewRemoteUpload = false

        for item in completed where !known.contains(item.id) {
            known.insert(item.id)
            switch item.metadata.direction {
            case .download:
                sawNewLocalDownload = true
            case .upload:
                sawNewRemoteUpload = true
            }
        }
        guard sawNewLocalDownload || sawNewRemoteUpload else { return }
        TransferRefreshTracker.completedIDsByWindow[windowInstanceID] = known

        TransferRefreshTracker.debounceTasksByWindow[windowInstanceID]?.cancel()
        TransferRefreshTracker.debounceTasksByWindow[windowInstanceID] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            if sawNewLocalDownload {
                await refreshLocalDirectory(localCurrentURL, recordHistory: false)
            }
            if sawNewRemoteUpload, currentSession != nil {
                await refreshRemoteDirectory(recordHistory: false)
            }
        }
    }
}
