import Foundation
import SparkleCore
import SparkleSecurity

struct DownloadConflictPlan: Sendable {
    let destination: URL
    let resumeOffset: Int64
}

struct UploadConflictPlan: Sendable {
    let destination: RemotePath
    let resumeDirectOffset: Int64?
}

struct DownloadConflictRequest: Sendable {
    let metadata: TransferTaskMetadata
    let safeDest: URL
    let partialURL: URL
    let baseDir: URL
    let remoteMeta: RemoteFileMetadata?
}

struct UploadConflictRequest: Sendable {
    let metadata: TransferTaskMetadata
    let localURL: URL
    let localSize: Int64
    let localModified: Date?
    let remotePath: RemotePath
    let remoteFS: any RemoteFileSystem
}

struct DownloadPartialPreparation: Sendable {
    let baseDir: URL
    let safeDest: URL
    let partialURL: URL
    let existingOffset: Int64
    let remoteMeta: RemoteFileMetadata?
}

extension TransferQueue {
    public func resumeAll() async {
        let resumableIDs = snapshots.values
            .filter { snapshot in
                switch snapshot.status {
                case .paused, .interrupted, .failed:
                    true
                default:
                    false
                }
            }
            .map(\.id)
        for id in resumableIDs {
            await retry(id: id)
        }
    }

    func prepareDownloadPartial(
        metadata: TransferTaskMetadata,
        remotePath: RemotePath,
        localURL: URL,
        remoteFS: any RemoteFileSystem
    ) async throws -> DownloadPartialPreparation {
        let baseDir = localURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        let safeDest = try PathValidator.safeLocalDestination(
            filename: localURL.lastPathComponent,
            baseDirectory: baseDir
        )
        let partialName = ".\(safeDest.lastPathComponent).sparklesftp.\(metadata.id.uuidString).part"
        let partialURL = baseDir.appendingPathComponent(partialName)

        let existingOffset = try await resolveDownloadOffset(
            taskID: metadata.id,
            remotePath: remotePath,
            partialURL: partialURL,
            remoteFS: remoteFS
        )
        let remoteMeta = try? await remoteFS.metadata(at: remotePath)
        if existingOffset == 0 {
            try? FileManager.default.removeItem(at: partialURL)
            await resetCheckpointBytes(id: metadata.id)
        }
        await recordCheckpointContext(
            id: metadata.id,
            remoteSize: remoteMeta?.size ?? metadata.totalBytes,
            remoteModificationTime: remoteMeta?.modificationTime,
            partialLocalPath: partialURL.path
        )
        return DownloadPartialPreparation(
            baseDir: baseDir,
            safeDest: safeDest,
            partialURL: partialURL,
            existingOffset: existingOffset,
            remoteMeta: remoteMeta
        )
    }

    func resolveConflictDestination(_ req: DownloadConflictRequest) async throws -> DownloadConflictPlan? {
        guard FileManager.default.fileExists(atPath: req.safeDest.path) else {
            return DownloadConflictPlan(destination: req.safeDest, resumeOffset: 0)
        }
        let attrs = try? FileManager.default.attributesOfItem(atPath: req.safeDest.path)
        let existingSize = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        let existingModified = attrs?[.modificationDate] as? Date
        let resolution = await conflictResolver.resolve(
            ConflictContext(
                taskID: req.metadata.id,
                direction: .download,
                sourceDisplayPath: req.metadata.source.displayPath,
                destinationDisplayPath: req.safeDest.path,
                existingSize: existingSize,
                incomingSize: req.remoteMeta?.size ?? req.metadata.totalBytes,
                existingModifiedAt: existingModified,
                incomingModifiedAt: req.remoteMeta?.modificationTime
            ),
            originalFilename: req.safeDest.lastPathComponent,
            overridePolicy: req.metadata.conflictPolicyOverride
        )
        switch resolution {
        case .skip:
            return nil
        case .overwrite:
            return DownloadConflictPlan(destination: req.safeDest, resumeOffset: 0)
        case .resume:
            let seedOffset = prepareResumedPartialFile(
                existingDest: req.safeDest,
                partialURL: req.partialURL,
                existingSize: existingSize,
                totalIncoming: req.remoteMeta?.size ?? req.metadata.totalBytes
            )
            return DownloadConflictPlan(destination: req.safeDest, resumeOffset: seedOffset)
        case let .rename(newName):
            let renamed = try PathValidator.safeLocalDestination(filename: newName, baseDirectory: req.baseDir)
            return DownloadConflictPlan(destination: renamed, resumeOffset: 0)
        }
    }

    func resolveRemoteUploadDestination(_ req: UploadConflictRequest) async throws -> UploadConflictPlan? {
        guard let existingMeta = try? await req.remoteFS.metadata(at: req.remotePath) else {
            return UploadConflictPlan(destination: req.remotePath, resumeDirectOffset: nil)
        }
        let resolution = await conflictResolver.resolve(
            ConflictContext(
                taskID: req.metadata.id,
                direction: .upload,
                sourceDisplayPath: req.localURL.path,
                destinationDisplayPath: req.remotePath.rawValue,
                existingSize: existingMeta.size,
                incomingSize: req.localSize,
                existingModifiedAt: existingMeta.modificationTime,
                incomingModifiedAt: req.localModified
            ),
            originalFilename: req.remotePath.filename,
            overridePolicy: req.metadata.conflictPolicyOverride
        )
        switch resolution {
        case .skip:
            return nil
        case .overwrite:
            return UploadConflictPlan(destination: req.remotePath, resumeDirectOffset: nil)
        case .resume:
            let canResume = existingMeta.size > 0 && existingMeta.size < req.localSize
            return UploadConflictPlan(
                destination: req.remotePath,
                resumeDirectOffset: canResume ? existingMeta.size : nil
            )
        case let .rename(newName):
            let renamed = try PathValidator.canonicalizeRemote(newName, relativeTo: req.remotePath.parent)
            return UploadConflictPlan(destination: renamed, resumeDirectOffset: nil)
        }
    }

    func finalizeRemoteUploadRename(
        remoteFS: any RemoteFileSystem,
        tempPath: RemotePath,
        finalPath: RemotePath
    ) async throws {
        do {
            try await remoteFS.rename(from: tempPath, to: finalPath)
        } catch {
            // Strict RFC SFTP v3 servers reject rename over an existing destination without prior removal.
            try? await remoteFS.delete(at: finalPath, isDirectory: false)
            try await remoteFS.rename(from: tempPath, to: finalPath)
        }
    }

    private func prepareResumedPartialFile(
        existingDest: URL,
        partialURL: URL,
        existingSize: Int64,
        totalIncoming: Int64
    ) -> Int64 {
        guard existingSize > 0, existingSize < totalIncoming else {
            return 0
        }
        if FileManager.default.fileExists(atPath: partialURL.path) {
            try? FileManager.default.removeItem(at: partialURL)
        }
        do {
            try FileManager.default.copyItem(at: existingDest, to: partialURL)
            return existingSize
        } catch {
            return 0
        }
    }
}
