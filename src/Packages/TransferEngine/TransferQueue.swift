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

    @TaskLocal static var currentWorkerToken: UUID?

    var snapshots: [UUID: TransferSnapshot] = [:]
    var lastJournalPersistAt: [UUID: Date] = [:]
    var activeTasks: [UUID: Task<Void, Never>] = [:]
    var activeWorkerTokens: [UUID: UUID] = [:]
    var lastProgressSequence: [UUID: UInt64] = [:]
    var skippedIDs: Set<UUID> = []
    var cancelledIDs: Set<UUID> = []
    var streamContinuations: [UUID: AsyncStream<[TransferSnapshot]>.Continuation] = [:]
    var snapshotFlushTask: Task<Void, Never>?

    public init(
        maxGlobalConcurrent: Int = 4,
        maxPerHostConcurrent: Int = 3,
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
        snapshotFlushTask?.cancel()
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

    public func updateDefaultConflictPolicies(
        upload: TransferConflictPolicy,
        download: TransferConflictPolicy
    ) async {
        await conflictResolver.updateDefaultPolicies(upload: upload, download: download)
    }

    public func applyConflictRule(_ policy: TransferConflictPolicy, scope: TransferConflictScope) async {
        await conflictResolver.applyQueueRule(policy, scope: scope)
    }

    public func clearConflictRules() async {
        await conflictResolver.clearQueueRules()
    }

    public func clearFinished() async {
        await clearCompletedAndFailed(removeCompleted: true, removeFailedAndCancelled: true)
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
        skippedIDs.remove(metadata.id)
        await scheduler.enqueue(metadata)
        await persistSnapshot(initial)
        broadcastSnapshots()
        await scheduleNextIfAvailable()
        return metadata.id
    }

    public func cancel(id: UUID) async {
        cancelledIDs.insert(id)
        activeWorkerTokens.removeValue(forKey: id)
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
        guard let existing = snapshots[id], !existing.status.isTerminal else { return }
        cancelledIDs.insert(id)
        activeWorkerTokens.removeValue(forKey: id)
        await scheduler.removePending(id: id)
        if let task = activeTasks.removeValue(forKey: id) {
            task.cancel()
        }
        let diskBytes = existing.metadata.direction == .download
            ? Self.measureLocalPartialBytes(checkpoint: existing.checkpoint)
            : 0
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
        await scheduleNextIfAvailable()
    }

    public func pauseAll() async {
        let pausableIDs = snapshots.values
            .filter { $0.status.isActive || $0.status == .queued }
            .map(\.id)
        for id in pausableIDs {
            await pause(id: id)
        }
    }

    public func retry(id: UUID) async {
        guard let existing = snapshots[id], !existing.status.isActive else { return }
        activeWorkerTokens.removeValue(forKey: id)
        activeTasks.removeValue(forKey: id)?.cancel()
        cancelledIDs.remove(id)
        skippedIDs.remove(id)
        lastProgressSequence.removeValue(forKey: id)
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
        snapshots[id] = queued
        await scheduler.enqueue(existing.metadata)
        await persistSnapshot(queued)
        broadcastSnapshots()
        await scheduleNextIfAvailable()
    }

    func scheduleNextIfAvailable() async {
        while let next = await scheduler.nextAdmissibleTask() {
            // Re-verify task was not cancelled while waiting in scheduler.
            if cancelledIDs.contains(next.id) {
                await scheduler.releaseSlot(forHost: next.targetHost)
                continue
            }
            let workerToken = UUID()
            activeWorkerTokens[next.id] = workerToken
            let worker = Task { [weak self] in
                guard let self else { return }
                await Self.$currentWorkerToken.withValue(workerToken) {
                    await executeTransfer(metadata: next, workerToken: workerToken)
                }
            }
            activeTasks[next.id] = worker
        }
    }
}
