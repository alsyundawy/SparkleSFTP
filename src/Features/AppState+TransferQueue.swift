import AppKit
import Foundation
import SparkleCore
import SparkleNetworking
import SparklePersistence
import SparkleTransferEngine

extension AppState {
    public var transferQueue: TransferQueue {
        if let existing = transferQueueInstance {
            return existing
        }
        let resolver = ConflictResolver(
            defaultPolicy: defaultUploadConflictPolicy,
            defaultDownloadPolicy: defaultDownloadConflictPolicy
        ) { [weak self] context in
            guard let self else { return .skip }
            return await promptConflictResolution(context)
        }
        let created = TransferQueue(
            maxGlobalConcurrent: maxGlobalConcurrentTransfers,
            maxPerHostConcurrent: maxPerHostConcurrentTransfers,
            journal: transferJournal,
            conflictResolver: resolver
        ) { [weak self] profileID in
            guard let self else { throw AppError.notConnected }
            return try await resolveRemoteFileSystem(for: profileID)
        }
        transferQueueInstance = created
        return created
    }

    public var defaultConflictPolicy: TransferConflictPolicy {
        get { defaultUploadConflictPolicy }
        set {
            defaultUploadConflictPolicy = newValue
            defaultDownloadConflictPolicy = newValue
        }
    }

    func resolveRemoteFileSystem(for profileID: UUID) throws -> any RemoteFileSystem {
        if let current = currentSession, current.profile.id == profileID {
            return current.service.fileSystem
        }
        guard let session = activeSessions.first(where: { $0.profile.id == profileID }) else {
            throw AppError.notConnected
        }
        return session.service.fileSystem
    }

    func ensureTransferObserverStarted() {
        if snapshotStreamTask == nil {
            startTransferObserver()
        }
    }

    func startTransferObserver() {
        snapshotStreamTask?.cancel()
        snapshotStreamTask = Task { [weak self] in
            guard let self else { return }
            let stream = await transferQueue.makeSnapshotsStream()
            for await snapshots in stream {
                if Task.isCancelled {
                    break
                }
                transferSnapshots = snapshots
                handleTransferSnapshotsChanged(snapshots)
                notifyTerminalTransfersIfNeeded(snapshots)
                if !pendingFolderPermissionJobs.isEmpty {
                    await finalizePendingFolderPermissions(from: snapshots)
                }
            }
        }
    }
}
