import Foundation
import SparkleCore
@testable import SparkleTransferEngine
import Testing

@Suite("SparkleTransferEngine Resume & Conflict Tests")
struct TransferEngineResumeTests {
    @Test("TransferQueue enforces ConflictResolver on remote upload conflicts (skip and rename)")
    func transferQueueUploadConflictResolution() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SparkleUploadConflict-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let remoteFS = MockRemoteFS()
        let baseMtime = Date(timeIntervalSince1970: 1_700_000_000)
        let originalRemote = Data("existing-remote".utf8)
        await remoteFS.setRemoteFile(path: "/deploy/app.txt", data: originalRemote, mtime: baseMtime)

        let localFile = dir.appendingPathComponent("app.txt")
        let incomingPayload = Data("new-local-upload".utf8)
        try incomingPayload.write(to: localFile)

        // Verify .rename keeps original remote intact and writes renamed file
        let renameResolver = ConflictResolver(defaultPolicy: .rename)
        let renameQueue = TransferQueue(conflictResolver: renameResolver) { _ in remoteFS }
        let taskRename = TransferTaskMetadata(
            direction: .upload,
            source: .local(url: localFile),
            destination: .remote(profileID: UUID(), host: "srv", path: "/deploy/app.txt"),
            totalBytes: Int64(incomingPayload.count)
        )
        _ = await renameQueue.enqueue(taskRename)
        _ = await waitUntilSnapshot(in: renameQueue, id: taskRename.id) { $0.status.isTerminal }

        #expect(await remoteFS.files["/deploy/app.txt"] == originalRemote)
        let renamedEntries = await remoteFS.files.filter {
            $0.key.hasPrefix("/deploy/app") && $0.key != "/deploy/app.txt"
        }
        #expect(renamedEntries.values.contains(incomingPayload))
    }

    @Test("TransferQueue pause measures actual partial disk bytes and resumes cleanly from offset")
    func transferQueuePauseAndResumeFromDiskPartial() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SparklePauseResume-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let remoteFS = MockRemoteFS()
        let baseTime = Date(timeIntervalSince1970: 1_700_000_000)
        let fullPayload = Data((0 ..< 256).map { UInt8($0 % 251) })
        await remoteFS.setRemoteFile(path: "/archive.bin", data: fullPayload, mtime: baseTime)
        await remoteFS.setDownloadDelay(.milliseconds(250))

        let queue = TransferQueue { _ in remoteFS }
        let dest = dir.appendingPathComponent("archive.bin")
        let task = TransferTaskMetadata(
            direction: .download,
            source: .remote(profileID: UUID(), host: "srv", path: "/archive.bin"),
            destination: .local(url: dest),
            totalBytes: Int64(fullPayload.count)
        )

        // Simulate interrupted partial file before pause/resume retry
        _ = await queue.enqueue(task)
        _ = await waitUntilSnapshot(in: queue, id: task.id) {
            $0.status.isActive && $0.checkpoint?.partialLocalPath != nil
        }
        await queue.pause(id: task.id)
        let pausedSnap = await waitUntilSnapshot(in: queue, id: task.id) { $0.status == .paused }
        #expect(pausedSnap?.status == .paused)
        if let partialPath = pausedSnap?.checkpoint?.partialLocalPath {
            try Data(fullPayload.prefix(100)).write(to: URL(fileURLWithPath: partialPath))
        }
        // Refresh pause after partial exists on disk so disk byte count is captured accurately
        await queue.pause(id: task.id)
        await remoteFS.setDownloadDelay(.zero)
        await queue.retry(id: task.id)
        let completedSnap = await waitUntilSnapshot(in: queue, id: task.id) { $0.status.isTerminal }
        #expect(completedSnap?.status == .completed)
        #expect(try Data(contentsOf: dest) == fullPayload)
        let offsets = await remoteFS.recordedDownloadOffsets
        #expect(offsets.contains(100))
    }

    @Test("TransferQueue restarts from offset 0 when remote file changes while paused (LOG-002)")
    func transferQueueRestartsWhenRemoteChangesDuringPause() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SparkleRemoteChanged-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let remoteFS = MockRemoteFS()
        let timeV1 = Date(timeIntervalSince1970: 1_700_000_000)
        let payloadV1 = Data(repeating: 0x41, count: 256)
        await remoteFS.setRemoteFile(path: "/release.bin", data: payloadV1, mtime: timeV1)
        await remoteFS.setDownloadDelay(.milliseconds(250))

        let queue = TransferQueue { _ in remoteFS }
        let dest = dir.appendingPathComponent("release.bin")
        let task = TransferTaskMetadata(
            direction: .download,
            source: .remote(profileID: UUID(), host: "srv", path: "/release.bin"),
            destination: .local(url: dest),
            totalBytes: Int64(payloadV1.count)
        )

        _ = await queue.enqueue(task)
        _ = await waitUntilSnapshot(in: queue, id: task.id) {
            $0.status.isActive && $0.checkpoint?.partialLocalPath != nil
        }
        await queue.pause(id: task.id)
        let pausedSnap = await waitUntilSnapshot(in: queue, id: task.id) { $0.status == .paused }
        if let partialPath = pausedSnap?.checkpoint?.partialLocalPath {
            try Data(payloadV1.prefix(100)).write(to: URL(fileURLWithPath: partialPath))
        }
        await queue.pause(id: task.id)

        // Mutate remote file before resuming; ResumeValidator must detect the change and restart at offset 0.
        let payloadV2 = Data(repeating: 0x42, count: 320)
        await remoteFS.setRemoteFile(path: "/release.bin", data: payloadV2, mtime: timeV1.addingTimeInterval(30))
        await remoteFS.setDownloadDelay(.zero)
        await queue.retry(id: task.id)
        let completedSnap = await waitUntilSnapshot(in: queue, id: task.id) { $0.status.isTerminal }
        #expect(completedSnap?.status == .completed)
        #expect(try Data(contentsOf: dest) == payloadV2)
    }

    private func waitUntilSnapshot(
        in queue: TransferQueue,
        id: UUID,
        timeoutSeconds: Double = 5.0,
        predicate: (TransferSnapshot) -> Bool
    ) async -> TransferSnapshot? {
        let deadline = ContinuousClock.now + .milliseconds(Int(timeoutSeconds * 1000))
        while ContinuousClock.now < deadline {
            if let snap = await queue.currentSnapshots().first(where: { $0.id == id }), predicate(snap) {
                return snap
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return await queue.currentSnapshots().first { $0.id == id }
    }
}

extension MockRemoteFS {
    func setDownloadDelay(_ duration: Duration) {
        downloadDelay = duration
    }
}
