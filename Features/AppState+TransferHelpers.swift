import Foundation
import SparkleCore
import SparkleFileManager
import SparkleSecurity
import SparkleTransferEngine

extension AppState {
    func enqueueLocalItemUpload(url: URL, isDirectory: Bool, into session: ActiveSessionModel) async {
        if !isDirectory {
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
            guard let remoteDest = try? session.currentRemotePath.appending(url.lastPathComponent) else { return }
            await enqueueFileUpload(
                localURL: url,
                remoteDest: remoteDest,
                size: size,
                session: session
            )
            return
        }

        do {
            let remoteDir = try session.currentRemotePath.appending(url.lastPathComponent)
            try await session.service.fileSystem.createDirectory(at: remoteDir)
            await enqueueLocalDirectoryContents(
                localDir: url,
                remoteDir: remoteDir,
                session: session,
                visited: [url.resolvingSymlinksInPath().path]
            )
        } catch {
            lastError = (error as? AppError) ?? .transferFailed(reason: error.localizedDescription)
        }
    }

    private func enqueueLocalDirectoryContents(
        localDir: URL,
        remoteDir: RemotePath,
        session: ActiveSessionModel,
        visited: Set<String>
    ) async {
        var nextVisited = visited
        guard let children = try? await localFileService.listDirectory(at: localDir) else { return }
        for child in children {
            let childURL = URL(fileURLWithPath: child.path.rawValue)
            guard let targetRemote = try? remoteDir.appending(child.name) else { continue }
            if child.isDirectory {
                let real = childURL.resolvingSymlinksInPath().path
                guard !nextVisited.contains(real) else { continue }
                nextVisited.insert(real)
                try? await session.service.fileSystem.createDirectory(at: targetRemote)
                await enqueueLocalDirectoryContents(
                    localDir: childURL,
                    remoteDir: targetRemote,
                    session: session,
                    visited: nextVisited
                )
            } else {
                await enqueueFileUpload(
                    localURL: childURL,
                    remoteDest: targetRemote,
                    size: child.size,
                    session: session
                )
            }
        }
    }

    private func enqueueFileUpload(
        localURL: URL,
        remoteDest: RemotePath,
        size: Int64,
        session: ActiveSessionModel
    ) async {
        let meta = TransferTaskMetadata(
            direction: .upload,
            source: .local(url: localURL),
            destination: .remote(profileID: session.profile.id, host: session.profile.host, path: remoteDest),
            totalBytes: size
        )
        _ = await transferQueue.enqueue(meta)
    }

    func enqueueRemoteItemDownload(
        file: RemoteFile,
        localParentDir: URL,
        session: ActiveSessionModel,
        visitedRemotePaths: Set<String> = []
    ) async {
        do {
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
                    totalBytes: file.size
                )
                _ = await transferQueue.enqueue(meta)
                return
            }

            var nextVisited = visitedRemotePaths
            guard !nextVisited.contains(file.path.rawValue) else { return }
            nextVisited.insert(file.path.rawValue)
            try FileManager.default.createDirectory(at: localDest, withIntermediateDirectories: true)
            let children = try await session.service.fileSystem.listDirectory(at: file.path)
            for child in children {
                await enqueueRemoteItemDownload(
                    file: child,
                    localParentDir: localDest,
                    session: session,
                    visitedRemotePaths: nextVisited
                )
            }
        } catch {
            lastError = (error as? AppError) ?? .transferFailed(reason: error.localizedDescription)
        }
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
            Task { @MainActor [weak self] in
                guard let self,
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
                _ = await transferQueue.enqueue(meta)
            }
        }
        remoteEditWatches[request.tempDir] = watcher
    }
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
private final class DigestTracker {
    var lastUploadedDigest: String

    init(initialDigest: String) {
        lastUploadedDigest = initialDigest
    }
}
