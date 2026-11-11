import Foundation
import SparkleCore
import SparkleFileManager
import SparkleSecurity
import SparkleTransferEngine

extension AppState {
    func enqueueLocalItemUpload(url: URL, isDirectory: Bool, into session: ActiveSessionModel) async {
        ensureTransferObserverStarted()
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let posixMode = (attrs?[.posixPermissions] as? NSNumber)?.uint32Value
        if !isDirectory {
            let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
            guard let remoteDest = try? session.currentRemotePath.appending(url.lastPathComponent) else { return }
            _ = await enqueueFileUpload(
                localURL: url,
                remoteDest: remoteDest,
                size: size,
                permissions: posixMode,
                session: session
            )
            return
        }

        do {
            let remoteDir = try session.currentRemotePath.appending(url.lastPathComponent)
            var collector = FolderTransferCollector()
            try await ensureRemoteDirectory(
                at: remoteDir,
                desiredPermissions: posixMode,
                sessionProfileID: session.profile.id,
                remoteFS: session.service.fileSystem,
                collector: &collector
            )
            try await enqueueLocalDirectoryContents(
                localDir: url,
                remoteDir: remoteDir,
                session: session,
                visited: [url.resolvingSymlinksInPath().path],
                collector: &collector
            )
            await registerOrApplyFolderPermissions(collector)
        } catch {
            lastError = (error as? AppError) ?? .transferFailed(reason: error.localizedDescription)
        }
    }

    private func ensureRemoteDirectory(
        at remoteDir: RemotePath,
        desiredPermissions: UInt32?,
        sessionProfileID: UUID,
        remoteFS: any RemoteFileSystem,
        collector: inout FolderTransferCollector
    ) async throws {
        if let existing = try? await remoteFS.metadata(at: remoteDir) {
            guard existing.isDirectory else {
                throw AppError.transferFailed(reason: "Remote path exists as a file: \(remoteDir.rawValue)")
            }
        } else {
            try await remoteFS.createDirectory(at: remoteDir)
        }
        if let perms = desiredPermissions {
            let exactMode = perms & 0o777
            // Keep owner rwx during folder upload so queued child files can be written into the directory.
            let uploadSafeMode = exactMode | 0o700
            try? await remoteFS.setPermissions(uploadSafeMode, at: remoteDir)
            let target = RemoteDirectoryPermissionTarget(path: remoteDir, mode: exactMode, profileID: sessionProfileID)
            collector.remoteDirectories.append(target)
        }
    }

    private func enqueueLocalDirectoryContents(
        localDir: URL,
        remoteDir: RemotePath,
        session: ActiveSessionModel,
        visited: Set<String>,
        collector: inout FolderTransferCollector
    ) async throws {
        var nextVisited = visited
        let children = try await localFileService.listDirectory(at: localDir, showHidden: true)
        for child in children {
            let childURL = URL(fileURLWithPath: child.path.rawValue)
            guard let targetRemote = try? remoteDir.appending(child.name) else { continue }
            if child.isSymlink {
                let resolvedPath = childURL.resolvingSymlinksInPath().path
                guard !nextVisited.contains(resolvedPath) else { continue }
            }
            if child.isDirectory {
                let real = childURL.resolvingSymlinksInPath().path
                guard !nextVisited.contains(real) else { continue }
                nextVisited.insert(real)
                try await ensureRemoteDirectory(
                    at: targetRemote,
                    desiredPermissions: child.permissions,
                    sessionProfileID: session.profile.id,
                    remoteFS: session.service.fileSystem,
                    collector: &collector
                )
                try await enqueueLocalDirectoryContents(
                    localDir: childURL,
                    remoteDir: targetRemote,
                    session: session,
                    visited: nextVisited,
                    collector: &collector
                )
            } else {
                let taskID = await enqueueFileUpload(
                    localURL: childURL,
                    remoteDest: targetRemote,
                    size: child.size,
                    permissions: child.permissions,
                    session: session
                )
                collector.taskIDs.insert(taskID)
            }
        }
    }

    @discardableResult
    private func enqueueFileUpload(
        localURL: URL,
        remoteDest: RemotePath,
        size: Int64,
        permissions: UInt32?,
        session: ActiveSessionModel
    ) async -> UUID {
        let meta = TransferTaskMetadata(
            direction: .upload,
            source: .local(url: localURL),
            destination: .remote(profileID: session.profile.id, host: session.profile.host, path: remoteDest),
            totalBytes: size,
            sourcePermissions: permissions
        )
        return await transferQueue.enqueue(meta)
    }

    func enqueueRemoteItemDownload(
        file: RemoteFile,
        localParentDir: URL,
        session: ActiveSessionModel
    ) async {
        ensureTransferObserverStarted()
        var collector = FolderTransferCollector()
        await traverseRemoteItemDownload(
            file: file,
            localParentDir: localParentDir,
            session: session,
            visitedRemotePaths: [],
            collector: &collector
        )
        await registerOrApplyFolderPermissions(collector)
    }

    private func traverseRemoteItemDownload(
        file: RemoteFile,
        localParentDir: URL,
        session: ActiveSessionModel,
        visitedRemotePaths: Set<String>,
        collector: inout FolderTransferCollector
    ) async {
        do {
            let safePerms: UInt32? = file.permissions > 0 ? (file.permissions & 0o777) : nil
            let localDest = try PathValidator.safeLocalDestination(
                filename: file.name,
                baseDirectory: localParentDir,
                symlinkTarget: file.symlinkTarget
            )
            if !file.isDirectory {
                let meta = TransferTaskMetadata(
                    direction: .download,
                    source: .remote(profileID: session.profile.id, host: session.profile.host, path: file.path),
                    destination: .local(url: localDest),
                    totalBytes: file.size,
                    sourcePermissions: safePerms
                )
                await collector.taskIDs.insert(transferQueue.enqueue(meta))
                return
            }
            var nextVisited = visitedRemotePaths
            let canonicalDir: RemotePath = if file.isSymlink {
                await (try? session.service.fileSystem.resolveSymlink(at: file.path)) ?? file.path
            } else {
                file.path
            }
            guard !nextVisited.contains(canonicalDir.rawValue) else { return }
            nextVisited.insert(canonicalDir.rawValue)
            nextVisited.insert(file.path.rawValue)
            try prepareDownloadDirectory(localDest: localDest, safePerms: safePerms, collector: &collector)
            let children = try await session.service.fileSystem.listDirectory(at: file.path)
            for child in children {
                if child.isSymlink {
                    let target = await (try? session.service.fileSystem.resolveSymlink(at: child.path)) ?? child.path
                    if nextVisited.contains(target.rawValue) || nextVisited.contains(child.path.rawValue) {
                        continue
                    }
                }
                await traverseRemoteItemDownload(
                    file: child,
                    localParentDir: localDest,
                    session: session,
                    visitedRemotePaths: nextVisited,
                    collector: &collector
                )
            }
        } catch {
            lastError = (error as? AppError) ?? .transferFailed(reason: error.localizedDescription)
        }
    }

    private func prepareDownloadDirectory(
        localDest: URL,
        safePerms: UInt32?,
        collector: inout FolderTransferCollector
    ) throws {
        try FileManager.default.createDirectory(at: localDest, withIntermediateDirectories: true)
        guard let safePerms else { return }
        let writableMode = (safePerms | 0o700) & 0o777
        try? FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: writableMode)],
            ofItemAtPath: localDest.path
        )
        collector.localDirectories.append((url: localDest, mode: safePerms))
    }

    public func quickLookRemoteFile(_ file: RemoteFile) async -> URL? {
        guard let session = currentSession, !file.isDirectory else { return nil }
        do {
            let tempDir = try SecureTempDirectory.createIsolatedWorkingDirectory(prefix: "SparkleQuickLook")
            let localPreview = try PathValidator.safeLocalDestination(filename: file.name, baseDirectory: tempDir)
            try await session.service.fileSystem.download(from: file.path, to: localPreview) { _ in }
            remoteEditWatches[tempDir] = LocalDirectoryWatcher()
            return localPreview
        } catch {
            lastError = (error as? AppError) ?? .transferFailed(reason: error.localizedDescription)
            return nil
        }
    }

    func watchEditedLocalFile(_ request: RemoteEditWatchRequest) {
        let watcher = LocalDirectoryWatcher()
        let digestTracker = DigestTracker(initialDigest: request.initialDigest)
        watcher.startWatching(directory: request.tempDir) { [weak self] in
            Task { @MainActor in
                guard let strongSelf = self,
                      FileManager.default.fileExists(atPath: request.localCopy.path),
                      let newDigest = try? await SHA256Verifier.computeHexDigest(of: request.localCopy),
                      newDigest != digestTracker.lastUploadedDigest
                else { return }
                digestTracker.lastUploadedDigest = newDigest
                let attrs = try? FileManager.default.attributesOfItem(atPath: request.localCopy.path)
                let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
                let meta = TransferTaskMetadata(
                    direction: .upload,
                    source: .local(url: request.localCopy),
                    destination: .remote(
                        profileID: request.profileID,
                        host: request.host,
                        path: request.remotePath
                    ),
                    totalBytes: size,
                    conflictPolicyOverride: .overwrite
                )
                _ = await strongSelf.transferQueue.enqueue(meta)
            }
        }
        remoteEditWatches[request.tempDir] = watcher
    }
}

@MainActor
private final class DigestTracker {
    var lastUploadedDigest: String

    init(initialDigest: String) {
        lastUploadedDigest = initialDigest
    }
}
