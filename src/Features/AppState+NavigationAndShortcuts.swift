import AppKit
import Foundation
import SparkleCore
import SparkleTransferEngine

struct FolderTransferCollector {
    var taskIDs: Set<UUID> = []
    var remoteDirectories: [RemoteDirectoryPermissionTarget] = []
    var localDirectories: [(url: URL, mode: UInt32)] = []
}

struct RemoteEditWatchRequest {
    let tempDir: URL
    let localCopy: URL
    let initialDigest: String
    let profileID: UUID
    let host: String
    let remotePath: RemotePath
}

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

extension AppState {
    func registerOrApplyFolderPermissions(_ collector: FolderTransferCollector) async {
        guard !collector.remoteDirectories.isEmpty || !collector.localDirectories.isEmpty else { return }
        let job = PendingFolderPermissionJob(
            remainingTaskIDs: collector.taskIDs,
            remoteDirectories: collector.remoteDirectories,
            localDirectories: collector.localDirectories
        )
        if job.remainingTaskIDs.isEmpty {
            await applyFolderPermissions(job)
            return
        }
        pendingFolderPermissionJobs.append(job)
        await finalizePendingFolderPermissions(from: transferQueue.currentSnapshots())
    }

    func finalizePendingFolderPermissions(from snapshots: [TransferSnapshot]) async {
        guard !pendingFolderPermissionJobs.isEmpty else { return }
        let terminalIDs = Set(snapshots.filter(\.status.isTerminal).map(\.id))
        var stillPending: [PendingFolderPermissionJob] = []
        var readyJobs: [PendingFolderPermissionJob] = []
        for var job in pendingFolderPermissionJobs {
            job.remainingTaskIDs.subtract(terminalIDs)
            if job.remainingTaskIDs.isEmpty {
                readyJobs.append(job)
            } else {
                stillPending.append(job)
            }
        }
        pendingFolderPermissionJobs = stillPending
        for job in readyJobs {
            await applyFolderPermissions(job)
        }
    }

    private func applyFolderPermissions(_ job: PendingFolderPermissionJob) async {
        let sortedRemote = job.remoteDirectories.sorted { $0.path.rawValue.count > $1.path.rawValue.count }
        for entry in sortedRemote {
            if let remoteFS = try? resolveRemoteFileSystem(for: entry.profileID) {
                try? await remoteFS.setPermissions(entry.mode & 0o777, at: entry.path)
            }
        }
        let sortedLocal = job.localDirectories.sorted { $0.url.path.count > $1.url.path.count }
        for entry in sortedLocal {
            try? FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: entry.mode & 0o777)],
                ofItemAtPath: entry.url.path
            )
        }
    }
}
