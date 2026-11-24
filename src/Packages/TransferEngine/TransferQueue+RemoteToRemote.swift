import Foundation
import SparkleCore
import SparkleSecurity

private final class RemoteToRemoteSeqBox: @unchecked Sendable { // JUSTIFICATION: NSLock guards sequence counter.
    private let lock = NSLock()
    private var nextValue: UInt64 = 1

    func next() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        let val = nextValue
        nextValue &+= 1
        return val
    }
}

extension TransferQueue {
    func performRemoteToRemoteAttempt(
        metadata: TransferTaskMetadata,
        srcProfileID: UUID,
        srcPath: RemotePath,
        dstProfileID: UUID,
        dstPath: RemotePath
    ) async throws {
        let srcFS = try await fileSystemResolver(srcProfileID)
        let dstFS = try await fileSystemResolver(dstProfileID)
        guard isStillActive(id: metadata.id) else { throw CancellationError() }

        let pipeDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SparkleRemotePipe",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: pipeDir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: Int16(0o700))]
        )
        let pipeFile = pipeDir.appendingPathComponent("\(UUID().uuidString).pipe")
        defer {
            try? FileManager.default.removeItem(at: pipeFile)
        }

        await updateStatus(id: metadata.id, status: .transferring(bytesPerSecond: 0))

        let srcMeta = try await srcFS.metadata(at: srcPath)
        let totalSize = srcMeta.size
        let seqBox = RemoteToRemoteSeqBox()

        // Phase 1: Stream from source remote endpoint to local pipe staging
        try await srcFS.download(from: srcPath, to: pipeFile, offset: 0) { [weak self] progress in
            let seq = seqBox.next()
            let scaled = TransferProgress(
                bytesTransferred: progress.bytesTransferred / 2,
                totalBytes: max(progress.totalBytes, totalSize),
                bytesPerSecond: progress.bytesPerSecond
            )
            Task { [weak self] in
                await self?.handleProgress(id: metadata.id, sequence: seq, progress: scaled)
            }
        }

        guard isStillActive(id: metadata.id) else { throw CancellationError() }

        // Phase 2: Stream from local pipe staging to destination remote endpoint
        try await dstFS.upload(from: pipeFile, to: dstPath, offset: 0) { [weak self] progress in
            let seq = seqBox.next()
            let half = totalSize / 2
            let scaled = TransferProgress(
                bytesTransferred: half + (progress.bytesTransferred / 2),
                totalBytes: max(progress.totalBytes, totalSize),
                bytesPerSecond: progress.bytesPerSecond
            )
            Task { [weak self] in
                await self?.handleProgress(id: metadata.id, sequence: seq, progress: scaled)
            }
        }
    }
}
