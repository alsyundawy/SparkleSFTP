import Foundation
import SparkleCore

extension TransferQueue {
    func executeTransfer(metadata: TransferTaskMetadata, workerToken: UUID) async {
        defer {
            Task { [weak self] in
                await self?.finalizeExecutionSlot(
                    taskID: metadata.id,
                    workerToken: workerToken,
                    host: metadata.targetHost
                )
            }
        }

        await updateStatus(id: metadata.id, status: .preparing)

        // Post-await reentrancy verification (RUN-003)
        guard isStillActive(id: metadata.id) else { return }

        do {
            try await runWithRetry(metadata: metadata)
            // Re-verify after transfer await before marking completed (RUN-003)
            guard isStillActive(id: metadata.id) else { return }
            let wasSkipped = skippedIDs.remove(metadata.id) != nil
            let existingProgress = snapshots[metadata.id]?.progress
            let finalTransferred = wasSkipped ? 0 : max(metadata.totalBytes, existingProgress?.bytesTransferred ?? 0)
            let finalTotal = wasSkipped ? metadata.totalBytes : max(
                metadata.totalBytes,
                existingProgress?.totalBytes ?? 0
            )
            let finalProgress = TransferProgress(
                bytesTransferred: finalTransferred,
                totalBytes: finalTotal,
                bytesPerSecond: 0
            )
            await updateSnapshot(id: metadata.id, status: .completed, progress: finalProgress)
        } catch is CancellationError {
            // Status already set by cancel()/pause(); avoid overwriting with failed.
            return
        } catch {
            guard isStillActive(id: metadata.id) else { return }
            let mapped = (error as? AppError) ?? .transferFailed(reason: error.localizedDescription)
            await updateStatus(id: metadata.id, status: .failed(mapped))
        }
    }
}
