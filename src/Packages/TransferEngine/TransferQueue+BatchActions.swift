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
}
