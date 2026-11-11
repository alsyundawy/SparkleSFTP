import Foundation
import SparkleCore
import SparkleSecurity
import SparkleTransferEngine

public struct SyncExecutionReport: Sendable, Equatable {
    public let appliedCount: Int
    public let skippedDryRun: Bool
}

public struct SyncExecutionTarget: Sendable {
    public let localRoot: URL
    public let remoteRoot: RemotePath
    public let profileID: UUID
    public let host: String
    public let remoteFS: any RemoteFileSystem

    public init(
        localRoot: URL,
        remoteRoot: RemotePath,
        profileID: UUID,
        host: String,
        remoteFS: any RemoteFileSystem
    ) {
        self.localRoot = localRoot
        self.remoteRoot = remoteRoot
        self.profileID = profileID
        self.host = host
        self.remoteFS = remoteFS
    }
}

/// Executes validated non-stale SyncPlans across Upload, Download, and Bidirectional modes (LOG-003, TASK-108).
public actor SyncExecutor {
    private let transferQueue: TransferQueue

    public init(transferQueue: TransferQueue) {
        self.transferQueue = transferQueue
    }

    public func execute(
        plan: SyncPlan,
        target: SyncExecutionTarget,
        dryRun: Bool,
        now: Date = Date()
    ) async throws -> SyncExecutionReport {
        guard !plan.isStale(at: now) else {
            throw AppError.planExpired
        }
        if dryRun {
            return SyncExecutionReport(appliedCount: 0, skippedDryRun: true)
        }

        var count = 0
        for action in plan.actions {
            try Task.checkCancellation()
            try await applyAction(action, target: target)
            count += 1
        }
        return SyncExecutionReport(appliedCount: count, skippedDryRun: false)
    }

    private func applyAction(_ action: SyncAction, target: SyncExecutionTarget) async throws {
        let remoteTarget = try PathValidator.canonicalizeRemote(action.relativePath, relativeTo: target.remoteRoot)
        let localURL = try resolveSafeLocalURL(relativePath: action.relativePath, localRoot: target.localRoot)

        switch action.transferDirection {
        case .upload:
            try await applyUploadAction(action, localURL: localURL, remoteTarget: remoteTarget, target: target)
        case .download:
            try await applyDownloadAction(action, localURL: localURL, remoteTarget: remoteTarget, target: target)
        }
    }

    private func applyUploadAction(
        _ action: SyncAction,
        localURL: URL,
        remoteTarget: RemotePath,
        target: SyncExecutionTarget
    ) async throws {
        switch action.kind {
        case .create:
            if action.isDirectory {
                try await target.remoteFS.createDirectory(at: remoteTarget)
            } else {
                await enqueueTransfer(
                    direction: .upload,
                    localURL: localURL,
                    remoteTarget: remoteTarget,
                    target: target,
                    size: action.size
                )
            }
        case .update:
            try await verifyUnchangedRemote(action: action, remoteTarget: remoteTarget, remoteFS: target.remoteFS)
            await enqueueTransfer(
                direction: .upload,
                localURL: localURL,
                remoteTarget: remoteTarget,
                target: target,
                size: action.size,
                conflictPolicyOverride: .overwrite
            )
        case .delete:
            try await verifyUnchangedRemote(action: action, remoteTarget: remoteTarget, remoteFS: target.remoteFS)
            try await target.remoteFS.delete(at: remoteTarget, isDirectory: action.isDirectory)
        }
    }

    private func applyDownloadAction(
        _ action: SyncAction,
        localURL: URL,
        remoteTarget: RemotePath,
        target: SyncExecutionTarget
    ) async throws {
        switch action.kind {
        case .create:
            if action.isDirectory {
                try FileManager.default.createDirectory(at: localURL, withIntermediateDirectories: true)
            } else {
                try FileManager.default.createDirectory(
                    at: localURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                await enqueueTransfer(
                    direction: .download,
                    localURL: localURL,
                    remoteTarget: remoteTarget,
                    target: target,
                    size: action.size
                )
            }
        case .update:
            try await verifyUnchangedRemote(action: action, remoteTarget: remoteTarget, remoteFS: target.remoteFS)
            await enqueueTransfer(
                direction: .download,
                localURL: localURL,
                remoteTarget: remoteTarget,
                target: target,
                size: action.size,
                conflictPolicyOverride: .overwrite
            )
        case .delete:
            if FileManager.default.fileExists(atPath: localURL.path) {
                try FileManager.default.removeItem(at: localURL)
            }
        }
    }

    private func resolveSafeLocalURL(relativePath: String, localRoot: URL) throws -> URL {
        let parts = relativePath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !parts.isEmpty else {
            throw AppError.pathTraversal(attempted: relativePath)
        }
        let resolvedRoot = localRoot.standardizedFileURL.resolvingSymlinksInPath()
        let rootPrefix = resolvedRoot.path.hasSuffix("/") ? resolvedRoot.path : resolvedRoot.path + "/"
        var currentDir = resolvedRoot
        for segment in parts.dropLast() {
            if segment == "." || segment == ".." || segment.contains("\0") {
                throw AppError.pathTraversal(attempted: relativePath)
            }
            currentDir = currentDir.appendingPathComponent(segment, isDirectory: true)
            let resolvedParent = currentDir.resolvingSymlinksInPath()
            guard resolvedParent.path == resolvedRoot.path || resolvedParent.path.hasPrefix(rootPrefix) else {
                throw AppError.symlinkTraversal(destination: resolvedParent.path)
            }
        }
        return try PathValidator.safeLocalDestination(filename: parts[parts.count - 1], baseDirectory: currentDir)
    }

    private func verifyUnchangedRemote(
        action: SyncAction,
        remoteTarget: RemotePath,
        remoteFS: any RemoteFileSystem
    ) async throws {
        let liveMeta = try await remoteFS.metadata(at: remoteTarget)
        if let expected = action.expectedMtime,
           let live = liveMeta.modificationTime,
           abs(expected.timeIntervalSince(live)) > 2.0 {
            throw AppError.syncConflict(path: remoteTarget.rawValue)
        }
    }

    private func enqueueTransfer(
        direction: TransferDirection,
        localURL: URL,
        remoteTarget: RemotePath,
        target: SyncExecutionTarget,
        size: Int64,
        conflictPolicyOverride: TransferConflictPolicy? = nil
    ) async {
        let sourceEndpoint: TransferEndpoint = direction == .upload
            ? .local(url: localURL)
            : .remote(profileID: target.profileID, host: target.host, path: remoteTarget)
        let destEndpoint: TransferEndpoint = direction == .upload
            ? .remote(profileID: target.profileID, host: target.host, path: remoteTarget)
            : .local(url: localURL)
        let meta = TransferTaskMetadata(
            direction: direction,
            source: sourceEndpoint,
            destination: destEndpoint,
            totalBytes: size,
            conflictPolicyOverride: conflictPolicyOverride
        )
        _ = await transferQueue.enqueue(meta)
    }
}
