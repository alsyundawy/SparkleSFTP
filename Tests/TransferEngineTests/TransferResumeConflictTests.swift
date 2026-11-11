import Foundation
import SparkleCore
@testable import SparkleTransferEngine
import Testing

private actor ResumeHoleRemoteFS: RemoteFileSystem {
    var payload: Data
    var mtime: Date
    var recordedOffsets: [Int64] = []

    init(payload: Data, mtime: Date) {
        self.payload = payload
        self.mtime = mtime
    }

    func listDirectory(at _: RemotePath) async throws -> [RemoteFile] {
        []
    }

    func metadata(at path: RemotePath) async throws -> RemoteFileMetadata {
        RemoteFileMetadata(
            path: path,
            size: Int64(payload.count),
            isDirectory: false,
            modificationTime: mtime
        )
    }

    func resolveSymlink(at path: RemotePath) async throws -> RemotePath {
        path
    }

    func download(
        from _: RemotePath,
        to localURL: URL,
        offset: Int64,
        onProgress: @escaping @Sendable (TransferProgress) -> Void
    ) async throws {
        recordedOffsets.append(offset)
        let tail = payload.dropFirst(Int(offset))
        if offset > 0, FileManager.default.fileExists(atPath: localURL.path) {
            let handle = try FileHandle(forUpdating: localURL)
            defer { try? handle.close() }
            try handle.seek(toOffset: UInt64(offset))
            try handle.write(contentsOf: tail)
        } else {
            try Data(tail).write(to: localURL, options: [.atomic])
        }
        onProgress(
            TransferProgress(
                bytesTransferred: Int64(payload.count),
                totalBytes: Int64(payload.count),
                bytesPerSecond: 1024
            )
        )
    }

    func upload(
        from _: URL,
        to _: RemotePath,
        offset _: Int64,
        onProgress _: @escaping @Sendable (TransferProgress) -> Void
    ) async throws {}

    func delete(at _: RemotePath, isDirectory _: Bool) async throws {}
    func rename(from _: RemotePath, to _: RemotePath) async throws {}
    func createDirectory(at _: RemotePath) async throws {}
    func setPermissions(_: UInt32, at _: RemotePath) async throws {}
}

@Suite("TransferQueue Resume Integrity & Conflict Naming Tests")
struct TransferResumeConflictTests {
    @Test("Download resume preserves larger .part offset instead of creating sparse zero holes")
    func downloadResumePreservesLargerPartialFile() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SparkleResumeGap-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let fullPayload = Data((0 ..< 600).map { UInt8($0 % 251) })
        let mtime = Date(timeIntervalSince1970: 1_700_000_000)
        let remoteFS = ResumeHoleRemoteFS(payload: fullPayload, mtime: mtime)
        let destURL = dir.appendingPathComponent("bundle.bin")
        let queue = TransferQueue(conflictResolver: ConflictResolver(defaultPolicy: .resume)) { _ in remoteFS }
        let taskID = try await seedPausedPartialDownload(
            queue: queue,
            dir: dir,
            destURL: destURL,
            fullPayload: fullPayload,
            mtime: mtime
        )
        await queue.retry(id: taskID)
        for _ in 0 ..< 100 {
            if let snap = await queue.currentSnapshots().first(where: { $0.id == taskID }),
               snap.status.isTerminal {
                #expect(snap.status == .completed)
                break
            }
            try? await Task.sleep(for: .milliseconds(25))
        }

        let offsets = await remoteFS.recordedOffsets
        #expect(offsets.contains(400))
        #expect(try Data(contentsOf: destURL) == fullPayload)
    }

    private func seedPausedPartialDownload(
        queue: TransferQueue,
        dir: URL,
        destURL: URL,
        fullPayload: Data,
        mtime: Date
    ) async throws -> UUID {
        try Data(fullPayload.prefix(100)).write(to: destURL)
        let taskID = UUID()
        let partialURL = dir
            .appendingPathComponent(".\(destURL.lastPathComponent).sparklesftp.\(taskID.uuidString).part")
        try Data(fullPayload.prefix(400)).write(to: partialURL)
        let metadata = TransferTaskMetadata(
            id: taskID,
            direction: .download,
            source: .remote(profileID: UUID(), host: "srv", path: "/bundle.bin"),
            destination: .local(url: destURL),
            totalBytes: Int64(fullPayload.count),
            conflictPolicyOverride: .resume
        )
        await queue.recordSeedSnapshotForTest(
            TransferSnapshot(
                metadata: metadata,
                status: .paused,
                progress: TransferProgress(
                    bytesTransferred: 400,
                    totalBytes: Int64(fullPayload.count),
                    bytesPerSecond: 0
                ),
                checkpoint: TransferCheckpoint(
                    bytesTransferred: 400,
                    remoteSize: Int64(fullPayload.count),
                    remoteModificationTime: mtime,
                    partialLocalPath: partialURL.path
                )
            )
        )
        return taskID
    }

    @Test("ConflictResolver uniqueName generates distinct filenames within rapid calls")
    func conflictResolverUniqueNameNeverCollides() {
        let names = (0 ..< 20).map { _ in ConflictResolver.uniqueName(from: "report.tar.gz") }
        #expect(Set(names).count == 20)
    }
}
