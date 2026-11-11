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
        let normalizedProgress: TransferProgress = switch status {
        case .completed:
            TransferProgress(
                bytesTransferred: max(existing.progress.bytesTransferred, existing.metadata.totalBytes),
                totalBytes: max(existing.progress.totalBytes, existing.metadata.totalBytes),
                bytesPerSecond: 0
            )
        case .paused, .interrupted, .cancelled, .failed:
            TransferProgress(
                bytesTransferred: existing.progress.bytesTransferred,
                totalBytes: existing.progress.totalBytes,
                bytesPerSecond: 0
            )
        default:
            existing.progress
        }
        await updateSnapshot(id: id, status: status, progress: normalizedProgress)
    }

    func updateSnapshot(id: UUID, status: TransferStatus, progress: TransferProgress) async {
        guard isCurrentWorkerValid(id: id),
              let existing = snapshots[id],
              !existing.status.isTerminal
        else { return }
        if existing.status == .paused, status != .paused, status != .cancelled, status != .interrupted {
            return
        }
        let monotonicProgress: TransferProgress = if status == .completed {
            TransferProgress(
                bytesTransferred: max(existing.progress.bytesTransferred, progress.bytesTransferred),
                totalBytes: max(existing.progress.totalBytes, progress.totalBytes),
                bytesPerSecond: 0
            )
        } else {
            progress
        }
        let updated = TransferSnapshot(
            metadata: existing.metadata,
            status: status,
            progress: monotonicProgress,
            checkpoint: TransferCheckpoint(
                bytesTransferred: monotonicProgress.bytesTransferred,
                remoteSize: existing.checkpoint?.remoteSize
                    ?? max(existing.metadata.totalBytes, monotonicProgress.totalBytes),
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

    func handleProgress(id: UUID, sequence: UInt64, progress: TransferProgress) async {
        guard isStillActive(id: id),
              let existing = snapshots[id],
              Self.isProgressWritableStatus(existing.status),
              sequence >= (lastProgressSequence[id] ?? 0)
        else { return }
        lastProgressSequence[id] = sequence
        let preliminaryTotal = max(existing.progress.totalBytes, max(progress.totalBytes, progress.bytesTransferred))
        let isComplete = preliminaryTotal > 0 && progress.bytesTransferred >= preliminaryTotal
        guard await throttler.shouldEmit(for: id, force: isComplete) else { return }
        // Re-verify state after suspension so stale progress never overwrites .finalizing/.completed/.paused
        guard isStillActive(id: id),
              let latest = snapshots[id],
              Self.isProgressWritableStatus(latest.status),
              sequence >= (lastProgressSequence[id] ?? 0)
        else { return }
        let safeTransferred = max(latest.progress.bytesTransferred, progress.bytesTransferred)
        let safeTotal = max(latest.progress.totalBytes, max(progress.totalBytes, safeTransferred))
        let monotonic = TransferProgress(
            bytesTransferred: safeTransferred,
            totalBytes: safeTotal,
            bytesPerSecond: progress.bytesPerSecond
        )
        await updateSnapshot(
            id: id,
            status: .transferring(bytesPerSecond: monotonic.bytesPerSecond),
            progress: monotonic
        )
    }

    private static func isProgressWritableStatus(_ status: TransferStatus) -> Bool {
        switch status {
        case .connecting, .transferring:
            true
        default:
            false
        }
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
            lastProgressSequence.removeValue(forKey: taskID)
            await throttler.clear(taskID: taskID)
        }
        if let paused = snapshots[taskID], paused.status == .paused {
            await reconcilePausedCheckpoint(paused)
        }
        await scheduler.releaseSlot(forHost: host)
        await scheduleNextIfAvailable()
    }

    private func reconcilePausedCheckpoint(_ paused: TransferSnapshot) async {
        guard paused.metadata.direction == .download else { return }
        let flushedBytes = Self.measureLocalPartialBytes(checkpoint: paused.checkpoint)
        guard flushedBytes > 0, flushedBytes != paused.checkpoint?.bytesTransferred else { return }
        let updated = TransferSnapshot(
            metadata: paused.metadata,
            status: .paused,
            progress: TransferProgress(
                bytesTransferred: max(flushedBytes, paused.progress.bytesTransferred),
                totalBytes: paused.progress.totalBytes,
                bytesPerSecond: 0
            ),
            checkpoint: TransferCheckpoint(
                bytesTransferred: flushedBytes,
                remoteSize: paused.checkpoint?.remoteSize ?? paused.metadata.totalBytes,
                remoteModificationTime: paused.checkpoint?.remoteModificationTime,
                partialLocalPath: paused.checkpoint?.partialLocalPath
            )
        )
        snapshots[paused.id] = updated
        await persistSnapshot(updated)
        broadcastSnapshots()
    }
}
