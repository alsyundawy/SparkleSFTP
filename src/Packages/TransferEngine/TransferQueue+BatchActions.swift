import Foundation
import SparkleCore

public extension TransferQueue {
    @discardableResult
    func enqueueBatch(_ items: [TransferTaskMetadata]) async -> [UUID] {
        guard !items.isEmpty else { return [] }
        var createdSnapshots: [TransferSnapshot] = []
        createdSnapshots.reserveCapacity(items.count)
        var records: [TransferJournalRecord] = []
        records.reserveCapacity(items.count)
        var ids: [UUID] = []
        ids.reserveCapacity(items.count)

        for metadata in items {
            let initial = TransferSnapshot(
                metadata: metadata,
                status: .queued,
                progress: TransferProgress(bytesTransferred: 0, totalBytes: metadata.totalBytes, bytesPerSecond: 0)
            )
            snapshots[metadata.id] = initial
            cancelledIDs.remove(metadata.id)
            skippedIDs.remove(metadata.id)
            createdSnapshots.append(initial)
            records.append(journalRecord(for: initial))
            ids.append(metadata.id)
        }

        await scheduler.enqueueBatch(items)
        if let journal {
            try? await journal.upsertBatch(records)
        }
        broadcastSnapshots(immediate: true)
        await scheduleNextIfAvailable()
        return ids
    }

    func cancelAll() async {
        await scheduler.removeAllPending()
        let activeEntries = Array(activeTasks.values)
        activeTasks.removeAll()
        activeWorkerTokens.removeAll()
        for task in activeEntries {
            task.cancel()
        }

        var updatedRecords: [TransferJournalRecord] = []
        for (id, existing) in snapshots where !existing.status.isTerminal {
            cancelledIDs.insert(id)
            lastProgressSequence.removeValue(forKey: id)
            let updated = TransferSnapshot(
                metadata: existing.metadata,
                status: .cancelled,
                progress: TransferProgress(
                    bytesTransferred: existing.progress.bytesTransferred,
                    totalBytes: existing.progress.totalBytes,
                    bytesPerSecond: 0
                ),
                checkpoint: existing.checkpoint
            )
            snapshots[id] = updated
            updatedRecords.append(journalRecord(for: updated))
        }
        if let journal, !updatedRecords.isEmpty {
            try? await journal.upsertBatch(updatedRecords)
        }
        broadcastSnapshots(immediate: true)
    }

    func retryAllFailed() async {
        await retryTasks { snapshot in
            switch snapshot.status {
            case .failed, .cancelled, .interrupted:
                true
            default:
                false
            }
        }
    }

    internal func retryTasks(matching predicate: (TransferSnapshot) -> Bool) async {
        let retryCandidates = snapshots.values.filter(predicate)
        guard !retryCandidates.isEmpty else { return }

        var metas: [TransferTaskMetadata] = []
        var records: [TransferJournalRecord] = []
        for existing in retryCandidates {
            activeWorkerTokens.removeValue(forKey: existing.id)
            activeTasks.removeValue(forKey: existing.id)?.cancel()
            cancelledIDs.remove(existing.id)
            skippedIDs.remove(existing.id)
            lastProgressSequence.removeValue(forKey: existing.id)
            let queued = TransferSnapshot(
                metadata: existing.metadata,
                status: .queued,
                progress: TransferProgress(
                    bytesTransferred: existing.progress.bytesTransferred,
                    totalBytes: existing.progress.totalBytes,
                    bytesPerSecond: 0
                ),
                checkpoint: existing.checkpoint
            )
            snapshots[existing.id] = queued
            metas.append(existing.metadata)
            records.append(journalRecord(for: queued))
        }
        await scheduler.enqueueBatch(metas)
        if let journal {
            try? await journal.upsertBatch(records)
        }
        broadcastSnapshots(immediate: true)
        await scheduleNextIfAvailable()
    }

    func clearCompleted() async {
        await clearCompletedAndFailed(removeCompleted: true, removeFailedAndCancelled: false)
    }

    func clearFailed() async {
        await clearCompletedAndFailed(removeCompleted: false, removeFailedAndCancelled: true)
    }

    internal func clearCompletedAndFailed(removeCompleted: Bool, removeFailedAndCancelled: Bool) async {
        var removedIDs: [UUID] = []
        snapshots = snapshots.filter { id, snapshot in
            let shouldRemove: Bool = switch snapshot.status {
            case .completed:
                removeCompleted
            case .failed, .cancelled:
                removeFailedAndCancelled
            default:
                false
            }
            if shouldRemove {
                removedIDs.append(id)
                return false
            }
            return true
        }
        guard !removedIDs.isEmpty else { return }
        if let journal {
            try? await journal.deleteBatch(ids: removedIDs)
        }
        broadcastSnapshots(immediate: true)
    }

    func pauseAll() async {
        let pausableIDs = snapshots.values
            .filter { $0.status.isActive || $0.status == .queued }
            .map(\.id)
        guard !pausableIDs.isEmpty else { return }

        var pausedSnapshots: [TransferSnapshot] = []
        for id in pausableIDs {
            guard let existing = snapshots[id], !existing.status.isTerminal else { continue }
            cancelledIDs.insert(id)
            activeWorkerTokens.removeValue(forKey: id)
            activeTasks.removeValue(forKey: id)?.cancel()
            let diskBytes = existing.metadata.direction == .download
                ? Self.measureLocalPartialBytes(checkpoint: existing.checkpoint)
                : 0
            let recordedBytes = max(existing.progress.bytesTransferred, diskBytes)
            let updated = TransferSnapshot(
                metadata: existing.metadata,
                status: .paused,
                progress: TransferProgress(
                    bytesTransferred: recordedBytes,
                    totalBytes: existing.progress.totalBytes,
                    bytesPerSecond: 0
                ),
                checkpoint: TransferCheckpoint(
                    bytesTransferred: diskBytes > 0 ? diskBytes : existing.progress.bytesTransferred,
                    remoteSize: existing.checkpoint?.remoteSize ?? existing.metadata.totalBytes,
                    remoteModificationTime: existing.checkpoint?.remoteModificationTime,
                    partialLocalPath: existing.checkpoint?.partialLocalPath
                )
            )
            snapshots[id] = updated
            pausedSnapshots.append(updated)
        }
        for id in pausableIDs {
            await scheduler.removePending(id: id)
        }
        for updated in pausedSnapshots where snapshots[updated.id]?.status == .paused {
            await persistSnapshot(updated)
        }
        broadcastSnapshots()
    }
}
