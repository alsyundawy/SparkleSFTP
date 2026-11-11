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

/// Executes validated non-stale SyncPlans with destructive action revalidation (LOG-003).
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
        let localSource = target.localRoot.appendingPathComponent(action.relativePath)

        switch action.kind {
        case .create:
            if action.isDirectory {
                try await target.remoteFS.createDirectory(at: remoteTarget)
            } else {
                await enqueueUpload(
                    localURL: localSource,
                    remoteTarget: remoteTarget,
                    target: target,
                    size: action.size
                )
            }
        case .update:
            try await verifyUnchangedRemote(action: action, remoteTarget: remoteTarget, remoteFS: target.remoteFS)
            await enqueueUpload(
                localURL: localSource,
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

    private func enqueueUpload(
        localURL: URL,
        remoteTarget: RemotePath,
        target: SyncExecutionTarget,
        size: Int64,
        conflictPolicyOverride: TransferConflictPolicy? = nil
    ) async {
        let meta = TransferTaskMetadata(
            direction: .upload,
            source: .local(url: localURL),
            destination: .remote(profileID: target.profileID, host: target.host, path: remoteTarget),
            totalBytes: size,
            conflictPolicyOverride: conflictPolicyOverride
        )
        _ = await transferQueue.enqueue(meta)
    }
}
