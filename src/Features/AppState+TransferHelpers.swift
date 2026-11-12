import Foundation
import SparkleCore
import SparkleFileManager
import SparkleSecurity
import SparkleTransferEngine

private struct FolderWalkAccumulator {
    var pendingBatch: [TransferTaskMetadata] = []
    var collector = FolderTransferCollector()
}

private struct LocalUploadWalkContext: Sendable {
    let profileID: UUID
    let host: String
    let remoteFS: any RemoteFileSystem
    let localFileService: LocalFileService
    let transferQueue: TransferQueue
}

private struct RemoteDownloadWalkContext: Sendable {
    let profileID: UUID
    let host: String
    let remoteFS: any RemoteFileSystem
    let transferQueue: TransferQueue
}

extension AppState {
    public nonisolated static func isMacOSMetadataFile(_ filename: String) -> Bool {
        filename == ".DS_Store" || filename.hasPrefix("._")
    }

    func enqueueLocalItemUpload(url: URL, isDirectory: Bool, into session: ActiveSessionModel) async {
        ensureTransferObserverStarted()
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let posixMode = (attrs?[.posixPermissions] as? NSNumber)?.uint32Value
        if !isDirectory {
            if Self.isMacOSMetadataFile(url.lastPathComponent) {
                return
            }
            let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
            guard let remoteDest = try? session.currentRemotePath.appending(url.lastPathComponent) else { return }
            let meta = TransferTaskMetadata(
                direction: .upload,
                source: .local(url: url),
                destination: .remote(profileID: session.profile.id, host: session.profile.host, path: remoteDest),
                totalBytes: size,
                sourcePermissions: posixMode
            )
            _ = await transferQueue.enqueue(meta)
            return
        }

        do {
            let remoteDir = try session.currentRemotePath.appending(url.lastPathComponent)
            let context = LocalUploadWalkContext(
                profileID: session.profile.id,
                host: session.profile.host,
                remoteFS: session.service.fileSystem,
                localFileService: localFileService,
                transferQueue: transferQueue
            )
            let collector = try await Task.detached(priority: .userInitiated) {
                try await Self.collectAndEnqueueLocalFolder(
                    localDir: url,
                    remoteDir: remoteDir,
                    posixMode: posixMode,
                    context: context
                )
            }.value
            await registerOrApplyFolderPermissions(collector)
        } catch {
            reportNonCancellationError(error, asBannerOnly: true)
        }
    }

    func enqueueRemoteItemDownload(
        file: RemoteFile,
        localParentDir: URL,
        session: ActiveSessionModel
    ) async {
        ensureTransferObserverStarted()
        if !file.isDirectory {
            await enqueueSingleRemoteDownload(file: file, localParentDir: localParentDir, session: session)
            return
        }
        do {
            let context = RemoteDownloadWalkContext(
                profileID: session.profile.id,
                host: session.profile.host,
                remoteFS: session.service.fileSystem,
                transferQueue: transferQueue
            )
            let collector = try await Task.detached(priority: .userInitiated) {
                try await Self.collectAndEnqueueRemoteFolder(
                    file: file,
                    localParentDir: localParentDir,
                    context: context
                )
            }.value
            await registerOrApplyFolderPermissions(collector)
        } catch {
            reportNonCancellationError(error, asBannerOnly: true)
        }
    }

    private func enqueueSingleRemoteDownload(
        file: RemoteFile,
        localParentDir: URL,
        session: ActiveSessionModel
    ) async {
        do {
            let safePerms: UInt32? = file.permissions > 0 ? (file.permissions & 0o777) : nil
            let localDest = try PathValidator.safeLocalDestination(
                filename: file.name,
                baseDirectory: localParentDir,
                symlinkTarget: file.symlinkTarget
            )
            let meta = TransferTaskMetadata(
                direction: .download,
                source: .remote(profileID: session.profile.id, host: session.profile.host, path: file.path),
                destination: .local(url: localDest),
                totalBytes: file.size,
                sourcePermissions: safePerms
            )
            _ = await transferQueue.enqueue(meta)
        } catch {
            reportNonCancellationError(error, asBannerOnly: true)
        }
    }

    private nonisolated static func collectAndEnqueueLocalFolder(
        localDir: URL,
        remoteDir: RemotePath,
        posixMode: UInt32?,
        context: LocalUploadWalkContext
    ) async throws -> FolderTransferCollector {
        var acc = FolderWalkAccumulator()
        try await ensureRemoteDirectory(
            at: remoteDir,
            desiredPermissions: posixMode,
            profileID: context.profileID,
            remoteFS: context.remoteFS,
            collector: &acc.collector
        )
        try await walkLocalDirectory(
            localDir: localDir,
            remoteDir: remoteDir,
            context: context,
            visited: [localDir.resolvingSymlinksInPath().path],
            accumulator: &acc
        )
        if !acc.pendingBatch.isEmpty {
            let ids = await context.transferQueue.enqueueBatch(acc.pendingBatch)
            acc.collector.taskIDs.formUnion(ids)
        }
        return acc.collector
    }

    private nonisolated static func walkLocalDirectory(
        localDir: URL,
        remoteDir: RemotePath,
        context: LocalUploadWalkContext,
        visited: Set<String>,
        accumulator: inout FolderWalkAccumulator
    ) async throws {
        try Task.checkCancellation()
        var nextVisited = visited
        let children = try await context.localFileService.listDirectory(at: localDir, showHidden: true)
        for child in children {
            try Task.checkCancellation()
            if Self.isMacOSMetadataFile(child.name) {
                continue
            }
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
                    profileID: context.profileID,
                    remoteFS: context.remoteFS,
                    collector: &accumulator.collector
                )
                try await walkLocalDirectory(
                    localDir: childURL,
                    remoteDir: targetRemote,
                    context: context,
                    visited: nextVisited,
                    accumulator: &accumulator
                )
            } else {
                let meta = TransferTaskMetadata(
                    direction: .upload,
                    source: .local(url: childURL),
                    destination: .remote(profileID: context.profileID, host: context.host, path: targetRemote),
                    totalBytes: child.size,
                    sourcePermissions: child.permissions
                )
                try await appendAndFlushIfNeeded(meta, queue: context.transferQueue, accumulator: &accumulator)
            }
        }
    }

    private nonisolated static func appendAndFlushIfNeeded(
        _ meta: TransferTaskMetadata,
        queue: TransferQueue,
        accumulator: inout FolderWalkAccumulator
    ) async throws {
        accumulator.pendingBatch.append(meta)
        if accumulator.pendingBatch.count >= 50 {
            try Task.checkCancellation()
            let ids = await queue.enqueueBatch(accumulator.pendingBatch)
            accumulator.collector.taskIDs.formUnion(ids)
            accumulator.pendingBatch.removeAll(keepingCapacity: true)
        }
    }

    private nonisolated static func ensureRemoteDirectory(
        at remoteDir: RemotePath,
        desiredPermissions: UInt32?,
        profileID: UUID,
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
            let uploadSafeMode = exactMode | 0o700
            try? await remoteFS.setPermissions(uploadSafeMode, at: remoteDir)
            collector.remoteDirectories.append(
                RemoteDirectoryPermissionTarget(path: remoteDir, mode: exactMode, profileID: profileID)
            )
        }
    }

    private nonisolated static func collectAndEnqueueRemoteFolder(
        file: RemoteFile,
        localParentDir: URL,
        context: RemoteDownloadWalkContext
    ) async throws -> FolderTransferCollector {
        var acc = FolderWalkAccumulator()
        try await walkRemoteDirectory(
            file: file,
            localParentDir: localParentDir,
            context: context,
            visitedRemotePaths: [],
            accumulator: &acc
        )
        if !acc.pendingBatch.isEmpty {
            let ids = await context.transferQueue.enqueueBatch(acc.pendingBatch)
            acc.collector.taskIDs.formUnion(ids)
        }
        return acc.collector
    }

    private nonisolated static func walkRemoteDirectory(
        file: RemoteFile,
        localParentDir: URL,
        context: RemoteDownloadWalkContext,
        visitedRemotePaths: Set<String>,
        accumulator: inout FolderWalkAccumulator
    ) async throws {
        try Task.checkCancellation()
        let safePerms: UInt32? = file.permissions > 0 ? (file.permissions & 0o777) : nil
        let localDest = try PathValidator.safeLocalDestination(
            filename: file.name,
            baseDirectory: localParentDir,
            symlinkTarget: file.symlinkTarget
        )
        if !file.isDirectory {
            let meta = TransferTaskMetadata(
                direction: .download,
                source: .remote(profileID: context.profileID, host: context.host, path: file.path),
                destination: .local(url: localDest),
                totalBytes: file.size,
                sourcePermissions: safePerms
            )
            try await appendAndFlushIfNeeded(meta, queue: context.transferQueue, accumulator: &accumulator)
            return
        }
        var nextVisited = visitedRemotePaths
        let canonicalDir: RemotePath = if file.isSymlink {
            await (try? context.remoteFS.resolveSymlink(at: file.path)) ?? file.path
        } else {
            file.path
        }
        guard !nextVisited.contains(canonicalDir.rawValue) else { return }
        nextVisited.insert(canonicalDir.rawValue)
        nextVisited.insert(file.path.rawValue)
        try prepareDownloadDirectory(localDest: localDest, safePerms: safePerms, collector: &accumulator.collector)
        let children = try await context.remoteFS.listDirectory(at: file.path)
        for child in children {
            if child.isSymlink {
                let target = await (try? context.remoteFS.resolveSymlink(at: child.path)) ?? child.path
                if nextVisited.contains(target.rawValue) || nextVisited.contains(child.path.rawValue) {
                    continue
                }
            }
            try await walkRemoteDirectory(
                file: child,
                localParentDir: localDest,
                context: context,
                visitedRemotePaths: nextVisited,
                accumulator: &accumulator
            )
        }
    }

    private nonisolated static func prepareDownloadDirectory(
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
        collector.localDirectories.append(LocalDirectoryPermissionTarget(url: localDest, mode: safePerms))
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
            reportNonCancellationError(error)
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
