import Foundation
import SparkleCore

extension TransferQueue {
    func persistSnapshot(_ snapshot: TransferSnapshot) async {
        guard let journal else { return }
        let errorMsg: String? = if case let .failed(appError) = snapshot.status {
            appError.errorDescription
        } else {
            nil
        }
        let record = TransferJournalRecord(
            id: snapshot.id,
            metadata: snapshot.metadata,
            statusCode: snapshot.status.statusCode,
            errorDescription: errorMsg,
            checkpoint: snapshot.checkpoint
        )
        try? await journal.upsert(record)
    }

    func orderedSnapshots() -> [TransferSnapshot] {
        snapshots.values.sorted { $0.metadata.createdAt > $1.metadata.createdAt }
    }

    func broadcastSnapshots() {
        guard !streamContinuations.isEmpty else { return }
        let ordered = orderedSnapshots()
        for (_, cont) in streamContinuations {
            cont.yield(ordered)
        }
    }

    func removeContinuation(id: UUID) {
        streamContinuations.removeValue(forKey: id)
    }

    static func measureLocalPartialBytes(checkpoint: TransferCheckpoint?) -> Int64 {
        guard let path = checkpoint?.partialLocalPath,
              FileManager.default.fileExists(atPath: path),
              let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        else {
            return 0
        }
        return (attrs[.size] as? NSNumber)?.int64Value ?? 0
    }

    func recordSeedSnapshotForTest(_ snapshot: TransferSnapshot) {
        snapshots[snapshot.id] = snapshot
    }

    func updateStatus(id: UUID, status: TransferStatus) async {
        guard let existing = snapshots[id] else { return }
        await updateSnapshot(id: id, status: status, progress: existing.progress)
    }

    func updateSnapshot(id: UUID, status: TransferStatus, progress: TransferProgress) async {
        guard isCurrentWorkerValid(id: id), let existing = snapshots[id] else { return }
        let updated = TransferSnapshot(
            metadata: existing.metadata,
            status: status,
            progress: progress,
            checkpoint: TransferCheckpoint(
                bytesTransferred: progress.bytesTransferred,
                remoteSize: existing.checkpoint?.remoteSize ?? max(existing.metadata.totalBytes, progress.totalBytes),
                remoteModificationTime: existing.checkpoint?.remoteModificationTime,
                partialLocalPath: existing.checkpoint?.partialLocalPath
            )
        )
        snapshots[id] = updated
        let now = Date()
        let statusChanged = existing.status.statusCode != status.statusCode
        let isPausedOrInterrupted = status == .paused || status == .interrupted
        let shouldPersist = statusChanged
            || status.isTerminal
            || isPausedOrInterrupted
            || (lastJournalPersistAt[id].map { now.timeIntervalSince($0) >= 2.0 } ?? true)
        if shouldPersist {
            await persistSnapshot(updated)
            if status.isTerminal || isPausedOrInterrupted {
                lastJournalPersistAt.removeValue(forKey: id)
            } else {
                lastJournalPersistAt[id] = now
            }
        }
        broadcastSnapshots()
    }

    func resetCheckpointBytes(id: UUID) async {
        guard isCurrentWorkerValid(id: id), let existing = snapshots[id] else { return }
        let zeroProgress = TransferProgress(
            bytesTransferred: 0,
            totalBytes: existing.progress.totalBytes,
            bytesPerSecond: 0
        )
        let updated = TransferSnapshot(
            metadata: existing.metadata,
            status: existing.status,
            progress: zeroProgress,
            checkpoint: TransferCheckpoint(
                bytesTransferred: 0,
                remoteSize: existing.checkpoint?.remoteSize ?? existing.metadata.totalBytes,
                remoteModificationTime: existing.checkpoint?.remoteModificationTime,
                partialLocalPath: existing.checkpoint?.partialLocalPath
            )
        )
        snapshots[id] = updated
        await persistSnapshot(updated)
    }

    func recordCheckpointContext(
        id: UUID,
        remoteSize: Int64,
        remoteModificationTime: Date?,
        partialLocalPath: String?
    ) async {
        guard isCurrentWorkerValid(id: id), let existing = snapshots[id] else { return }
        let updated = TransferSnapshot(
            metadata: existing.metadata,
            status: existing.status,
            progress: existing.progress,
            checkpoint: TransferCheckpoint(
                bytesTransferred: existing.checkpoint?.bytesTransferred ?? existing.progress.bytesTransferred,
                remoteSize: remoteSize,
                remoteModificationTime: remoteModificationTime,
                partialLocalPath: partialLocalPath
            )
        )
        snapshots[id] = updated
        await persistSnapshot(updated)
    }

    func handleProgress(id: UUID, progress: TransferProgress) async {
        guard isStillActive(id: id), let currentStatus = snapshots[id]?.status else { return }
        switch currentStatus {
        case .connecting, .transferring:
            break
        default:
            return
        }
        let isComplete = progress.totalBytes > 0 && progress.bytesTransferred >= progress.totalBytes
        guard await throttler.shouldEmit(for: id, force: isComplete) else { return }
        await updateSnapshot(
            id: id,
            status: .transferring(bytesPerSecond: progress.bytesPerSecond),
            progress: progress
        )
    }

    func isCurrentWorkerValid(id: UUID) -> Bool {
        guard let token = Self.currentWorkerToken else { return true }
        return activeWorkerTokens[id] == token
    }

    func isStillActive(id: UUID) -> Bool {
        !cancelledIDs.contains(id) && activeTasks[id] != nil && isCurrentWorkerValid(id: id)
    }

    func finalizeExecutionSlot(taskID: UUID, workerToken: UUID, host: String) async {
        if activeWorkerTokens[taskID] == workerToken {
            activeWorkerTokens.removeValue(forKey: taskID)
            activeTasks.removeValue(forKey: taskID)
            await throttler.clear(taskID: taskID)
        }
        await scheduler.releaseSlot(forHost: host)
        await scheduleNextIfAvailable()
    }
}
