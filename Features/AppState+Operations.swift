import AppKit
import Foundation
import SparkleCore
import SparkleFileManager
import SparkleSecurity
import SparkleTransferEngine

extension AppState {
    public func applyTransferConcurrencySettings() async {
        await transferQueue.updateConcurrencyLimits(
            maxGlobal: maxGlobalConcurrentTransfers,
            maxPerHost: maxPerHostConcurrentTransfers
        )
    }

    public func switchActivePane() {
        activePane = activePane == .left ? .right : .left
    }

    public func refreshLocalDirectory(_ url: URL) async {
        do {
            let items = try await localFileService.listDirectory(at: url)
            let sorted = await FileSortDescriptor.sortRemoteFiles(items, by: localSortDescriptor)
            localCurrentURL = url
            localFiles = PaginatedFileWindow(allFiles: sorted)
            localWatcher.startWatching(directory: url) { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    await self.refreshLocalDirectory(self.localCurrentURL)
                }
            }
        } catch {
            lastError = .transferFailed(reason: error.localizedDescription)
        }
    }

    public func refreshRemoteDirectory(at path: RemotePath? = nil) async {
        guard let idx = activeSessions.firstIndex(where: { $0.id == activeSessionID }) else { return }
        let targetPath = path ?? activeSessions[idx].currentRemotePath
        let sort = activeSessions[idx].sortDescriptor
        do {
            let items = try await activeSessions[idx].service.fileSystem.listDirectory(at: targetPath)
            let sorted = await FileSortDescriptor.sortRemoteFiles(items, by: sort)
            activeSessions[idx].currentRemotePath = targetPath
            activeSessions[idx].remoteFiles = PaginatedFileWindow(allFiles: sorted)
        } catch {
            lastError = (error as? AppError) ?? .transferFailed(reason: error.localizedDescription)
        }
    }

    public func sortLocalFiles(by field: FileSortField) async {
        if localSortDescriptor.field == field {
            localSortDescriptor.ascending.toggle()
        } else {
            localSortDescriptor = FileSortDescriptor(field: field, ascending: true)
        }
        let sorted = await FileSortDescriptor.sortRemoteFiles(localFiles.allFiles, by: localSortDescriptor)
        localFiles.replaceFiles(sorted)
    }

    public func sortRemoteFiles(by field: FileSortField) async {
        guard let idx = activeSessions.firstIndex(where: { $0.id == activeSessionID }) else { return }
        if activeSessions[idx].sortDescriptor.field == field {
            activeSessions[idx].sortDescriptor.ascending.toggle()
        } else {
            activeSessions[idx].sortDescriptor = FileSortDescriptor(field: field, ascending: true)
        }
        let sorted = await FileSortDescriptor.sortRemoteFiles(
            activeSessions[idx].remoteFiles.allFiles,
            by: activeSessions[idx].sortDescriptor
        )
        activeSessions[idx].remoteFiles.replaceFiles(sorted)
    }

    public func enqueueSelectedTransfer() async {
        guard let session = currentSession else { return }
        if activePane == .left {
            let selected = localFiles.allFiles.filter { selectedLocalFileIDs.contains($0.id) && !$0.isDirectory }
            for file in selected {
                let localURL = URL(fileURLWithPath: file.path.rawValue)
                if let remoteDest = try? session.currentRemotePath.appending(file.name) {
                    let meta = TransferTaskMetadata(
                        direction: .upload,
                        source: .local(url: localURL),
                        destination: .remote(
                            profileID: session.profile.id,
                            host: session.profile.host,
                            path: remoteDest
                        ),
                        totalBytes: file.size
                    )
                    _ = await transferQueue.enqueue(meta)
                }
            }
        } else {
            let selected = session.remoteFiles.allFiles.filter {
                session.selectedRemoteFileIDs.contains($0.id) && !$0.isDirectory
            }
            for file in selected {
                if let localDest = try? PathValidator.safeLocalDestination(
                    filename: file.name,
                    baseDirectory: localCurrentURL,
                    symlinkTarget: file.symlinkTarget
                ) {
                    let meta = TransferTaskMetadata(
                        direction: .download,
                        source: .remote(profileID: session.profile.id, host: session.profile.host, path: file.path),
                        destination: .local(url: localDest),
                        totalBytes: file.size
                    )
                    _ = await transferQueue.enqueue(meta)
                }
            }
        }
    }

    public func uploadDroppedFiles(_ urls: [URL]) async {
        guard let session = currentSession else { return }
        for url in urls where !url.hasDirectoryPath {
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
            if let remoteDest = try? session.currentRemotePath.appending(url.lastPathComponent) {
                let meta = TransferTaskMetadata(
                    direction: .upload,
                    source: .local(url: url),
                    destination: .remote(profileID: session.profile.id, host: session.profile.host, path: remoteDest),
                    totalBytes: size
                )
                _ = await transferQueue.enqueue(meta)
            }
        }
    }

    public func createFolder(named name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            if activePane == .left {
                _ = try await localFileService.createDirectory(named: trimmed, in: localCurrentURL)
                await refreshLocalDirectory(localCurrentURL)
            } else if let session = currentSession {
                let target = try session.currentRemotePath.appending(trimmed)
                try await session.service.fileSystem.createDirectory(at: target)
                await refreshRemoteDirectory()
            }
        } catch {
            lastError = (error as? AppError) ?? .transferFailed(reason: error.localizedDescription)
        }
    }

    public func deleteSelectedItems() async {
        do {
            if activePane == .left {
                let selected = localFiles.allFiles.filter { selectedLocalFileIDs.contains($0.id) }
                for item in selected {
                    try await localFileService.delete(itemAt: URL(fileURLWithPath: item.path.rawValue))
                }
                await refreshLocalDirectory(localCurrentURL)
            } else if let session = currentSession {
                let selected = session.remoteFiles.allFiles.filter { session.selectedRemoteFileIDs.contains($0.id) }
                for item in selected {
                    try await session.service.fileSystem.delete(at: item.path, isDirectory: item.isDirectory)
                }
                await refreshRemoteDirectory()
            }
        } catch {
            lastError = (error as? AppError) ?? .transferFailed(reason: error.localizedDescription)
        }
    }

    public func setRemotePermissions(_ mode: UInt32, for file: RemoteFile) async {
        guard let session = currentSession else { return }
        do {
            try await session.service.fileSystem.setPermissions(mode, at: file.path)
            await refreshRemoteDirectory()
        } catch {
            lastError = (error as? AppError) ?? .transferFailed(reason: error.localizedDescription)
        }
    }

    public func openRemoteFileInEditor(_ file: RemoteFile) async {
        guard let session = currentSession, !file.isDirectory else { return }
        let profileID = session.profile.id
        let host = session.profile.host
        let remotePath = file.path
        do {
            let tempDir = try SecureTempDirectory.createIsolatedWorkingDirectory(prefix: "SparkleEdit")
            let localCopy = try PathValidator.safeLocalDestination(filename: file.name, baseDirectory: tempDir)
            try await session.service.fileSystem.download(from: remotePath, to: localCopy) { _ in }

            NSWorkspace.shared.open(localCopy)
            let watcher = LocalDirectoryWatcher()
            watcher.startWatching(directory: tempDir) { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let attrs = try? FileManager.default.attributesOfItem(atPath: localCopy.path)
                    let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
                    let meta = TransferTaskMetadata(
                        direction: .upload,
                        source: .local(url: localCopy),
                        destination: .remote(profileID: profileID, host: host, path: remotePath),
                        totalBytes: size
                    )
                    _ = await self.transferQueue.enqueue(meta)
                }
            }
            remoteEditWatchers.append(watcher)
        } catch {
            lastError = (error as? AppError) ?? .transferFailed(reason: error.localizedDescription)
        }
    }
}
