import Foundation
import SparkleCore
import SparkleSecurity

/// Actor-isolated transfer execution queue enforcing:
/// - Post-await reentrancy guards (RUN-003)
/// - Weak task references + deinit cancellation (MEM-001)
/// - Per-host & global concurrency admission (SCALE-001)
/// - Atomic temporary-write + off-MainActor SHA-256 verify + rename (PERF-002, TASK-084)
/// - Durable crash recovery journal (TASK-085 / TASK-086)
public actor TransferQueue {
    public typealias FileSystemResolver = @Sendable (UUID) async throws -> any RemoteFileSystem

    let scheduler: TransferScheduler
    let throttler: ProgressThrottler
    let journal: (any TransferJournalProtocol)?
    let conflictResolver: ConflictResolver
    let fileSystemResolver: FileSystemResolver

    var snapshots: [UUID: TransferSnapshot] = [:]
    var lastJournalPersistAt: [UUID: Date] = [:]
    var activeTasks: [UUID: Task<Void, Never>] = [:]
    var cancelledIDs: Set<UUID> = []
    var streamContinuations: [UUID: AsyncStream<[TransferSnapshot]>.Continuation] = [:]

    public init(
        maxGlobalConcurrent: Int = 3,
        maxPerHostConcurrent: Int = 2,
        journal: (any TransferJournalProtocol)? = nil,
        conflictResolver: ConflictResolver = ConflictResolver(defaultPolicy: .overwrite),
        fileSystemResolver: @escaping FileSystemResolver
    ) {
        scheduler = TransferScheduler(
            maxGlobalConcurrent: maxGlobalConcurrent,
            maxPerHostConcurrent: maxPerHostConcurrent
        )
        throttler = ProgressThrottler()
        self.journal = journal
        self.conflictResolver = conflictResolver
        self.fileSystemResolver = fileSystemResolver
    }

    deinit {
        for (_, task) in activeTasks {
            task.cancel()
        }
        for (_, cont) in streamContinuations {
            cont.finish()
        }
    }

    public func makeSnapshotsStream() -> AsyncStream<[TransferSnapshot]> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<[TransferSnapshot]>.makeStream(
            bufferingPolicy: .bufferingNewest(10)
        )
        streamContinuations[id] = continuation
        continuation.yield(orderedSnapshots())
        continuation.onTermination = { [weak self] _ in
            Task { [weak self] in
                await self?.removeContinuation(id: id)
            }
        }
        return stream
    }

    public func currentSnapshots() -> [TransferSnapshot] {
        orderedSnapshots()
    }

    public func updateConcurrencyLimits(maxGlobal: Int, maxPerHost: Int) async {
        await scheduler.updateLimits(maxGlobalConcurrent: maxGlobal, maxPerHostConcurrent: maxPerHost)
        await scheduleNextIfAvailable()
    }

    public func updateDefaultConflictPolicy(_ policy: TransferConflictPolicy) async {
        await conflictResolver.updateDefaultPolicy(policy)
    }

    public func clearFinished() {
        snapshots = snapshots.filter { !$0.value.status.isTerminal }
        broadcastSnapshots()
    }

    public func restoreInterruptedFromJournal() async throws -> [TransferSnapshot] {
        guard let journal else { return [] }
        try? await journal.pruneOldEntries(maxEntries: 10000, maxAgeDays: 30)
        let interrupted = try await journal.reconcileInterruptedOnLaunch()
        for record in interrupted {
            let progress = TransferProgress(
                bytesTransferred: record.checkpoint?.bytesTransferred ?? 0,
                totalBytes: record.metadata.totalBytes,
                bytesPerSecond: 0
            )
            snapshots[record.id] = TransferSnapshot(
                metadata: record.metadata,
                status: .interrupted,
                progress: progress,
                checkpoint: record.checkpoint
            )
        }
        broadcastSnapshots()
        return orderedSnapshots()
    }

    @discardableResult
    public func enqueue(_ metadata: TransferTaskMetadata) async -> UUID {
        let initial = TransferSnapshot(
            metadata: metadata,
            status: .queued,
            progress: TransferProgress(bytesTransferred: 0, totalBytes: metadata.totalBytes, bytesPerSecond: 0)
        )
        snapshots[metadata.id] = initial
        cancelledIDs.remove(metadata.id)
        await scheduler.enqueue(metadata)
        await persistSnapshot(initial)
        broadcastSnapshots()
        await scheduleNextIfAvailable()
        return metadata.id
    }

    public func cancel(id: UUID) async {
        cancelledIDs.insert(id)
        await scheduler.removePending(id: id)
        if let task = activeTasks.removeValue(forKey: id) {
            task.cancel()
        }
        if let existing = snapshots[id] {
            let updated = TransferSnapshot(
                metadata: existing.metadata,
                status: .cancelled,
                progress: existing.progress,
                checkpoint: existing.checkpoint
            )
            snapshots[id] = updated
            await persistSnapshot(updated)
            broadcastSnapshots()
        }
        await scheduleNextIfAvailable()
    }

    public func pause(id: UUID) async {
        cancelledIDs.insert(id)
        await scheduler.removePending(id: id)
        if let task = activeTasks.removeValue(forKey: id) {
            task.cancel()
        }
        if let existing = snapshots[id] {
            let diskBytes = Self.measureLocalPartialBytes(checkpoint: existing.checkpoint)
            let recordedBytes = max(existing.progress.bytesTransferred, diskBytes)
            let adjustedProgress = TransferProgress(
                bytesTransferred: recordedBytes,
                totalBytes: existing.progress.totalBytes,
                bytesPerSecond: 0
            )
            let updated = TransferSnapshot(
                metadata: existing.metadata,
                status: .paused,
                progress: adjustedProgress,
                checkpoint: TransferCheckpoint(
                    bytesTransferred: diskBytes > 0 ? diskBytes : existing.progress.bytesTransferred,
                    remoteSize: existing.checkpoint?.remoteSize ?? existing.metadata.totalBytes,
                    remoteModificationTime: existing.checkpoint?.remoteModificationTime,
                    partialLocalPath: existing.checkpoint?.partialLocalPath
                )
            )
            snapshots[id] = updated
            await persistSnapshot(updated)
            broadcastSnapshots()
        }
        await scheduleNextIfAvailable()
    }

    public func retry(id: UUID) async {
        guard let existing = snapshots[id] else { return }
        cancelledIDs.remove(id)
        let queued = TransferSnapshot(
            metadata: existing.metadata,
            status: .queued,
            progress: existing.progress,
            checkpoint: existing.checkpoint
        )
        snapshots[id] = queued
        await scheduler.enqueue(existing.metadata)
        await persistSnapshot(queued)
        broadcastSnapshots()
        await scheduleNextIfAvailable()
    }

    private func scheduleNextIfAvailable() async {
        while let next = await scheduler.nextAdmissibleTask() {
            // Re-verify task was not cancelled while waiting in scheduler.
            if cancelledIDs.contains(next.id) {
                await scheduler.releaseSlot(forHost: next.targetHost)
                continue
            }
            let worker = Task { [weak self] in
                guard let self else { return }
                await executeTransfer(metadata: next)
            }
            activeTasks[next.id] = worker
        }
    }

    private func executeTransfer(metadata: TransferTaskMetadata) async {
        defer {
            Task { [weak self] in
                await self?.finalizeExecutionSlot(taskID: metadata.id, host: metadata.targetHost)
            }
        }

        await updateStatus(id: metadata.id, status: .preparing)

        // Post-await reentrancy verification (RUN-003)
        guard isStillActive(id: metadata.id) else { return }

        do {
            try await runWithRetry(metadata: metadata)
            // Re-verify after transfer await before marking completed (RUN-003)
            guard isStillActive(id: metadata.id) else { return }
            let finalProgress = TransferProgress(
                bytesTransferred: max(metadata.totalBytes, snapshots[metadata.id]?.progress.bytesTransferred ?? 0),
                totalBytes: max(metadata.totalBytes, snapshots[metadata.id]?.progress.totalBytes ?? 0),
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

    func isStillActive(id: UUID) -> Bool {
        !cancelledIDs.contains(id) && activeTasks[id] != nil
    }

    private func finalizeExecutionSlot(taskID: UUID, host: String) async {
        activeTasks.removeValue(forKey: taskID)
        await throttler.clear(taskID: taskID)
        await scheduler.releaseSlot(forHost: host)
        await scheduleNextIfAvailable()
    }
}
