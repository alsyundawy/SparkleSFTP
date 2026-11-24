import AppKit
import Foundation
import SparkleCore
import SparkleFileManager
import SparkleNetworking
import SparkleSecurity
import SparkleTerminal
import SparkleTransferEngine

public extension AppState {
    func applyTransferConcurrencySettings() async {
        await transferQueue.updateConcurrencyLimits(
            maxGlobal: maxGlobalConcurrentTransfers,
            maxPerHost: maxPerHostConcurrentTransfers
        )
        for session in activeSessions {
            if let sftp = session.service.connection as? SFTPService {
                await sftp.updatePipelineDepth(transferPipelineDepth)
            }
        }
    }

    func applyConflictPolicySettings() async {
        await transferQueue.updateDefaultConflictPolicies(
            upload: defaultUploadConflictPolicy,
            download: defaultDownloadConflictPolicy
        )
    }

    func resetConflictQueueRules() async {
        activeQueueConflictRules.removeAll()
        hasActiveConflictQueueRules = false
        await transferQueue.clearConflictRules()
    }

    func handleExternalURL(_ url: URL) async {
        if url.isFileURL {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
                if isDir.boolValue {
                    await refreshLocalDirectory(url)
                } else {
                    await refreshLocalDirectory(url.deletingLastPathComponent())
                    selectedLocalFileIDs = [url.path]
                }
            }
        } else if let scheme = url.scheme?.lowercased(), ["sftp", "ftps", "ssh"].contains(scheme) {
            guard let host = url.host, !host.isEmpty else { return }
            let port = url.port ?? (scheme == "ftps" ? 990 : 22)
            let user = url.user ?? ""
            let rawPath = url.path.isEmpty ? "/" : url.path
            let proto: ProtocolType = (scheme == "ftps") ? .ftpsExplicit : .sftp

            if let existing = profiles.first(where: {
                $0.host.lowercased() == host.lowercased() && $0.port == port && $0.username == user
            }) {
                selectedProfileID = existing.id
            } else {
                let profile = ConnectionProfile(
                    name: "\(host):\(port)",
                    protocolType: proto,
                    host: host,
                    port: port,
                    username: user,
                    defaultRemotePath: RemotePath(rawValue: rawPath)
                )
                try? await connectionStore.saveProfile(profile)
                await refreshProfilesAndGroups()
                selectedProfileID = profile.id
            }
        }
    }

    func openInExternalTerminal(_ profile: ConnectionProfile) async {
        if externalTerminalApp == .internalTerminal {
            await openEnlargedTerminalWindow()
            statusBannerMessage = "Opened \(profile.host) in Enlarged Terminal"
            return
        }
        if toolchainReport.libraries.isEmpty {
            await refreshToolchainReport()
        }
        let jumpProfile = profile.jumpHostProfileID.flatMap { jumpID in
            profiles.first { $0.id == jumpID }
        }
        do {
            let launchedApp = try await ExternalTerminalLauncher.launchSession(
                for: profile,
                preferredApp: externalTerminalApp,
                report: toolchainReport,
                jumpProfile: jumpProfile
            )
            statusBannerMessage = "Opened \(profile.host) in \(launchedApp)"
        } catch {
            reportNonCancellationError(error)
        }
    }

    func switchActivePane() {
        activePane = activePane == .left ? .right : .left
    }

    func goBackInActivePane() async {
        if activePane == .left {
            guard let prevPath = localHistory.goBack() else { return }
            await refreshLocalDirectory(URL(fileURLWithPath: prevPath), recordHistory: false)
        } else if let idx = activeSessions.firstIndex(where: { $0.id == activeSessionID }),
                  let prevPath = activeSessions[idx].history.goBack() {
            await refreshRemoteDirectory(at: RemotePath(rawValue: prevPath), recordHistory: false)
        }
    }

    func goForwardInActivePane() async {
        if activePane == .left {
            guard let nextPath = localHistory.goForward() else { return }
            await refreshLocalDirectory(URL(fileURLWithPath: nextPath), recordHistory: false)
        } else if let idx = activeSessions.firstIndex(where: { $0.id == activeSessionID }),
                  let nextPath = activeSessions[idx].history.goForward() {
            await refreshRemoteDirectory(at: RemotePath(rawValue: nextPath), recordHistory: false)
        }
    }

    func refreshLocalDirectory(_ url: URL, recordHistory: Bool = true) async {
        do {
            let items = try await localFileService.listDirectory(at: url)
            let sorted = await FileSortDescriptor.sortRemoteFiles(items, by: localSortDescriptor)
            let oldURL = localCurrentURL
            localCurrentURL = url
            if recordHistory {
                localHistory.navigate(to: url.path)
                BookmarkManager.shared.recordPath(url.path, isRemote: false)
                if !Self.isSynchronizingBrowsing,
                   let session = currentSession,
                   let syncPath = BookmarkManager.shared.computeSynchronizedPath(
                       from: oldURL.path,
                       to: url.path,
                       currentOppositePath: session.currentRemotePath.rawValue
                   ) {
                    Self.isSynchronizingBrowsing = true
                    await refreshRemoteDirectory(at: RemotePath(rawValue: syncPath))
                    Self.isSynchronizingBrowsing = false
                }
            }
            localFiles = PaginatedFileWindow(allFiles: sorted)
            if oldURL != url {
                selectedLocalFileIDs.removeAll()
            }
            syncCurrentTabLocalSnapshot()
            if watchedLocalURL?.standardizedFileURL != url.standardizedFileURL {
                watchedLocalURL = url
                localWatcher.startWatching(directory: url) { [weak self] in
                    Task { @MainActor in
                        guard let strongSelf = self else { return }
                        await strongSelf.refreshLocalDirectory(strongSelf.localCurrentURL, recordHistory: false)
                    }
                }
            }
        } catch {
            reportNonCancellationError(error)
        }
    }

    func refreshRemoteDirectory(at path: RemotePath? = nil, recordHistory: Bool = true) async {
        guard let initialIdx = activeSessions.firstIndex(where: { $0.id == activeSessionID }) else { return }
        let sessionID = activeSessions[initialIdx].id
        let fileSystem = activeSessions[initialIdx].service.fileSystem
        let targetPath = path ?? activeSessions[initialIdx].currentRemotePath
        let sort = activeSessions[initialIdx].sortDescriptor
        ActivityLogger.shared.logCommand("LIST \(targetPath.rawValue)")
        do {
            let items = try await fileSystem.listDirectory(at: targetPath)
            let sorted = await FileSortDescriptor.sortRemoteFiles(items, by: sort)
            guard let refreshedIdx = activeSessions.firstIndex(where: { $0.id == sessionID }) else { return }
            let oldPath = activeSessions[refreshedIdx].currentRemotePath
            activeSessions[refreshedIdx].currentRemotePath = targetPath
            if recordHistory {
                activeSessions[refreshedIdx].history.navigate(to: targetPath.rawValue)
                let host = activeSessions[refreshedIdx].profile.host
                BookmarkManager.shared.recordPath(targetPath.rawValue, isRemote: true, hostIdentifier: host)
                if !Self.isSynchronizingBrowsing,
                   let syncPath = BookmarkManager.shared.computeSynchronizedPath(
                       from: oldPath.rawValue,
                       to: targetPath.rawValue,
                       currentOppositePath: localCurrentURL.path
                   ) {
                    let localURL = URL(fileURLWithPath: syncPath)
                    var isDir: ObjCBool = false
                    if FileManager.default.fileExists(atPath: syncPath, isDirectory: &isDir), isDir.boolValue {
                        Self.isSynchronizingBrowsing = true
                        await refreshLocalDirectory(localURL)
                        Self.isSynchronizingBrowsing = false
                    }
                }
            }
            activeSessions[refreshedIdx].remoteFiles = PaginatedFileWindow(allFiles: sorted)
            if oldPath != targetPath {
                activeSessions[refreshedIdx].selectedRemoteFileIDs.removeAll()
            }
            ActivityLogger.shared.logResponse(
                "Directory listing of \"\(targetPath.rawValue)\" successful (\(items.count) items)"
            )
        } catch {
            ActivityLogger.shared.logError(
                "Failed to list \"\(targetPath.rawValue)\": \(error.localizedDescription)"
            )
            reportNonCancellationError(error)
        }
    }

    func loadMoreFilesInActivePane() {
        if activePane == .left {
            localFiles.loadNextPage()
        } else if let idx = activeSessions.firstIndex(where: { $0.id == activeSessionID }) {
            activeSessions[idx].remoteFiles.loadNextPage()
        }
    }

    func sortLocalFiles(by field: FileSortField) async {
        if localSortDescriptor.field == field {
            localSortDescriptor.ascending.toggle()
        } else {
            localSortDescriptor = FileSortDescriptor(field: field, ascending: true)
        }
        let sorted = await FileSortDescriptor.sortRemoteFiles(localFiles.allFiles, by: localSortDescriptor)
        localFiles.replaceFiles(sorted)
        syncCurrentTabLocalSnapshot()
    }

    func selectAllLocalFiles() {
        selectedLocalFileIDs = Set(localFiles.visibleFiles.map(\.id))
        activePane = .left
    }

    func deselectAllLocalFiles() {
        selectedLocalFileIDs.removeAll()
        activePane = .left
    }

    func selectAllRemoteFiles() {
        guard let idx = activeSessions.firstIndex(where: { $0.id == activeSessionID }) else { return }
        activeSessions[idx].selectedRemoteFileIDs = Set(activeSessions[idx].remoteFiles.visibleFiles.map(\.id))
        activePane = .right
    }

    func deselectAllRemoteFiles() {
        guard let idx = activeSessions.firstIndex(where: { $0.id == activeSessionID }) else { return }
        activeSessions[idx].selectedRemoteFileIDs.removeAll()
        activePane = .right
    }

    func filterLocalFiles(_ query: String) {
        localFiles.setFilter(query)
    }

    func filterRemoteFiles(_ query: String) {
        guard let idx = activeSessions.firstIndex(where: { $0.id == activeSessionID }) else { return }
        activeSessions[idx].remoteFiles.setFilter(query)
    }

    func syncRemotePaneToTerminalDirectory(_ directory: String) async {
        guard let session = currentSession,
              session.currentRemotePath.rawValue != directory
        else { return }
        await refreshRemoteDirectory(at: RemotePath(rawValue: directory))
    }

    func sortRemoteFiles(by field: FileSortField) async {
        guard let initialIdx = activeSessions.firstIndex(where: { $0.id == activeSessionID }) else { return }
        let sessionID = activeSessions[initialIdx].id
        if activeSessions[initialIdx].sortDescriptor.field == field {
            activeSessions[initialIdx].sortDescriptor.ascending.toggle()
        } else {
            activeSessions[initialIdx].sortDescriptor = FileSortDescriptor(field: field, ascending: true)
        }
        let sortDescriptor = activeSessions[initialIdx].sortDescriptor
        let snapshotFiles = activeSessions[initialIdx].remoteFiles.allFiles
        let sorted = await FileSortDescriptor.sortRemoteFiles(snapshotFiles, by: sortDescriptor)
        guard let refreshedIdx = activeSessions.firstIndex(where: { $0.id == sessionID }) else { return }
        activeSessions[refreshedIdx].remoteFiles.replaceFiles(sorted)
    }

    func enqueueSelectedTransfer() async {
        guard let session = currentSession else { return }
        if activePane == .left {
            let selected = localFiles.allFiles.filter { selectedLocalFileIDs.contains($0.id) }
            for file in selected {
                let localURL = URL(fileURLWithPath: file.path.rawValue)
                await enqueueLocalItemUpload(url: localURL, isDirectory: file.isDirectory, into: session)
            }
        } else {
            let selected = session.remoteFiles.allFiles.filter {
                session.selectedRemoteFileIDs.contains($0.id)
            }
            for file in selected {
                await enqueueRemoteItemDownload(file: file, localParentDir: localCurrentURL, session: session)
            }
        }
    }

    func uploadDroppedFiles(_ urls: [URL]) async {
        guard let session = currentSession else { return }
        for url in urls where url.isFileURL {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? url.hasDirectoryPath
            await enqueueLocalItemUpload(url: url, isDirectory: isDir, into: session)
        }
    }

    func createFolder(named name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            if activePane == .left {
                _ = try await localFileService.createDirectory(named: trimmed, in: localCurrentURL)
                await refreshLocalDirectory(localCurrentURL, recordHistory: false)
            } else if let session = currentSession {
                let target = try session.currentRemotePath.appending(trimmed)
                try await session.service.fileSystem.createDirectory(at: target)
                await refreshRemoteDirectory(recordHistory: false)
            }
        } catch {
            reportNonCancellationError(error)
        }
    }

    func renameItem(_ item: RemoteFile, to newName: String, isLocal: Bool) async {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != item.name else { return }
        do {
            if isLocal {
                let sourceURL = URL(fileURLWithPath: item.path.rawValue)
                _ = try await localFileService.rename(itemAt: sourceURL, to: trimmed)
                await refreshLocalDirectory(localCurrentURL, recordHistory: false)
            } else if let session = currentSession {
                let dest = try item.path.parent.appending(trimmed)
                try await session.service.fileSystem.rename(from: item.path, to: dest)
                await refreshRemoteDirectory(recordHistory: false)
            }
        } catch {
            reportNonCancellationError(error)
        }
    }

    func deleteSelectedItems() async {
        do {
            if activePane == .left {
                let selected = localFiles.allFiles.filter { selectedLocalFileIDs.contains($0.id) }
                for item in selected {
                    try await localFileService.delete(itemAt: URL(fileURLWithPath: item.path.rawValue))
                }
                await refreshLocalDirectory(localCurrentURL, recordHistory: false)
            } else if let session = currentSession {
                let selected = session.remoteFiles.allFiles.filter { session.selectedRemoteFileIDs.contains($0.id) }
                for item in selected {
                    try await session.service.fileSystem.delete(at: item.path, isDirectory: item.isDirectory)
                }
                await refreshRemoteDirectory(recordHistory: false)
            }
        } catch {
            reportNonCancellationError(error)
        }
    }

    func setRemotePermissions(_ mode: UInt32, for file: RemoteFile) async {
        guard let session = currentSession else { return }
        do {
            try await session.service.fileSystem.setPermissions(mode, at: file.path)
            await refreshRemoteDirectory(recordHistory: false)
        } catch {
            reportNonCancellationError(error)
        }
    }

    func openRemoteFileInEditor(_ file: RemoteFile) async {
        guard let session = currentSession, !file.isDirectory else { return }
        var stagingTempDir: URL?
        do {
            let tempDir = try SecureTempDirectory.createIsolatedWorkingDirectory(prefix: "SparkleEdit")
            stagingTempDir = tempDir
            let localCopy = try PathValidator.safeLocalDestination(filename: file.name, baseDirectory: tempDir)
            try await session.service.fileSystem.download(from: file.path, to: localCopy) { _ in }
            let initialDigest = try await SHA256Verifier.computeHexDigest(of: localCopy)
            NSWorkspace.shared.open(localCopy)
            statusBannerMessage = "Opened \(file.name) in editor (auto-upload on change)"
            let watchReq = RemoteEditWatchRequest(
                tempDir: tempDir, localCopy: localCopy, initialDigest: initialDigest,
                profileID: session.profile.id, host: session.profile.host, remotePath: file.path
            )
            watchEditedLocalFile(watchReq)
            stagingTempDir = nil
        } catch {
            if let stagingTempDir { try? FileManager.default.removeItem(at: stagingTempDir) }
            reportNonCancellationError(error, asBannerOnly: true)
        }
    }
}
