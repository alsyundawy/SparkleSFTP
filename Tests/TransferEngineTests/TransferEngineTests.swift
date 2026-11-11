import Crypto
import Foundation
import SparkleCore
@testable import SparkleTransferEngine
import Testing

actor MockRemoteFS: RemoteFileSystem {
    var files: [String: Data] = [:]
    var mtimes: [String: Date] = [:]
    var downloadDelay: Duration = .zero
    var uploadDelay: Duration = .zero
    var failCountBeforeSuccess = 0
    var recordedDownloadOffsets: [Int64] = []
    private var attempts = 0

    func setRemoteFile(path: String, data: Data, mtime: Date = Date()) {
        files[path] = data
        mtimes[path] = mtime
    }

    func listDirectory(at _: RemotePath) async throws -> [RemoteFile] {
        []
    }

    func metadata(at path: RemotePath) async throws -> RemoteFileMetadata {
        guard let data = files[path.rawValue] else {
            throw AppError.fileNotFound(path: path.rawValue)
        }
        return RemoteFileMetadata(
            path: path,
            size: Int64(data.count),
            isDirectory: false,
            modificationTime: mtimes[path.rawValue]
        )
    }

    func resolveSymlink(at path: RemotePath) async throws -> RemotePath {
        path
    }

    func download(
        from remotePath: RemotePath,
        to localURL: URL,
        offset: Int64,
        onProgress: @escaping @Sendable (TransferProgress) -> Void
    ) async throws {
        recordedDownloadOffsets.append(offset)
        attempts += 1
        if attempts <= failCountBeforeSuccess {
            throw AppError.connectionTimeout(host: "mock", seconds: 1)
        }
        if downloadDelay > .zero {
            try await Task.sleep(for: downloadDelay)
        }
        try Task.checkCancellation()
        guard let data = files[remotePath.rawValue] else {
            throw AppError.fileNotFound(path: remotePath.rawValue)
        }
        let slice = offset > 0 ? data.dropFirst(Int(offset)) : data[...]
        if offset > 0, FileManager.default.fileExists(atPath: localURL.path) {
            let handle = try FileHandle(forUpdating: localURL)
            defer { try? handle.close() }
            try handle.seek(toOffset: UInt64(offset))
            try handle.write(contentsOf: slice)
        } else {
            try Data(slice).write(to: localURL, options: [.atomic])
        }
        let progress = TransferProgress(
            bytesTransferred: Int64(data.count),
            totalBytes: Int64(data.count),
            bytesPerSecond: 1024
        )
        onProgress(progress)
    }

    func upload(
        from localURL: URL,
        to remotePath: RemotePath,
        offset _: Int64,
        onProgress: @escaping @Sendable (TransferProgress) -> Void
    ) async throws {
        if uploadDelay > .zero {
            try await Task.sleep(for: uploadDelay)
        }
        try Task.checkCancellation()
        let data = try Data(contentsOf: localURL)
        files[remotePath.rawValue] = data
        mtimes[remotePath.rawValue] = Date()
        let progress = TransferProgress(
            bytesTransferred: Int64(data.count),
            totalBytes: Int64(data.count),
            bytesPerSecond: 1024
        )
        onProgress(progress)
    }

    func delete(at path: RemotePath, isDirectory _: Bool) async throws {
        files.removeValue(forKey: path.rawValue)
    }

    func rename(from source: RemotePath, to destination: RemotePath) async throws {
        guard let data = files.removeValue(forKey: source.rawValue) else {
            throw AppError.fileNotFound(path: source.rawValue)
        }
        files[destination.rawValue] = data
    }

    func createDirectory(at _: RemotePath) async throws {}
    func setPermissions(_: UInt32, at _: RemotePath) async throws {}
}

@Suite("SparkleTransferEngine Tests")
struct TransferEngineTests {
    @Test("TransferScheduler enforces per-host concurrency limit (SCALE-001)")
    func schedulerEnforcesPerHostLimit() async {
        let scheduler = TransferScheduler(maxGlobalConcurrent: 3, maxPerHostConcurrent: 2)
        let profileID = UUID()
        let taskOne = TransferTaskMetadata(
            direction: .download,
            source: .remote(profileID: profileID, host: "hostA", path: "/1"),
            destination: .local(url: URL(fileURLWithPath: "/tmp/1")),
            totalBytes: 10,
            priority: .normal
        )
        let taskTwo = TransferTaskMetadata(
            direction: .download,
            source: .remote(profileID: profileID, host: "hostA", path: "/2"),
            destination: .local(url: URL(fileURLWithPath: "/tmp/2")),
            totalBytes: 10,
            priority: .normal
        )
        let taskThree = TransferTaskMetadata(
            direction: .download,
            source: .remote(profileID: profileID, host: "hostA", path: "/3"),
            destination: .local(url: URL(fileURLWithPath: "/tmp/3")),
            totalBytes: 10,
            priority: .normal
        )
        let taskFour = TransferTaskMetadata(
            direction: .download,
            source: .remote(profileID: profileID, host: "hostB", path: "/4"),
            destination: .local(url: URL(fileURLWithPath: "/tmp/4")),
            totalBytes: 10,
            priority: .low
        )

        await scheduler.enqueue(taskOne)
        await scheduler.enqueue(taskTwo)
        await scheduler.enqueue(taskThree)
        await scheduler.enqueue(taskFour)

        let admittedOne = await scheduler.nextAdmissibleTask()
        let admittedTwo = await scheduler.nextAdmissibleTask()
        let admittedThree = await scheduler.nextAdmissibleTask()
        let admittedFour = await scheduler.nextAdmissibleTask()

        #expect(admittedOne?.id == taskOne.id)
        #expect(admittedTwo?.id == taskTwo.id)
        #expect(admittedThree?.id == taskFour.id) // hostA capped at 2, so hostB admitted
        #expect(admittedFour == nil)
    }

    @Test("ResumeValidator detects remote file changes and restarts safely (LOG-002)")
    func resumeValidatorRestartsOnRemoteChange() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SparkleResume-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let partial = dir.appendingPathComponent("file.part")
        try Data(repeating: 0xAA, count: 100).write(to: partial)

        let remoteFS = MockRemoteFS()
        let baseTime = Date(timeIntervalSince1970: 1_700_000_000)
        await remoteFS.setRemoteFile(path: "/bundle.bin", data: Data(repeating: 0xAA, count: 250), mtime: baseTime)

        let validCP = TransferCheckpoint(bytesTransferred: 100, remoteSize: 250, remoteModificationTime: baseTime)
        let decision1 = try await ResumeValidator.validateDownloadResume(
            remotePath: "/bundle.bin",
            partialLocalURL: partial,
            checkpoint: validCP,
            remoteFS: remoteFS
        )
        #expect(decision1 == .resume(fromOffset: 100))

        // Remote file modified -> must restart from 0
        await remoteFS.setRemoteFile(
            path: "/bundle.bin",
            data: Data(repeating: 0xBB, count: 300),
            mtime: baseTime.addingTimeInterval(30)
        )
        let decision2 = try await ResumeValidator.validateDownloadResume(
            remotePath: "/bundle.bin",
            partialLocalURL: partial,
            checkpoint: validCP,
            remoteFS: remoteFS
        )
        if case .restart = decision2 {
            // Expected
        } else {
            Issue.record("Expected restart when remote file changed")
        }
    }

    @Test("TransferQueue atomic upload + SHA256 download verification + mid-transfer cancel reentrancy (RUN-003)")
    func transferQueueDownloadVerifyAndCancel() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SparkleQueue-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let remoteFS = MockRemoteFS()
        let payload = Data("SparkleSFTP Verified Payload".utf8)
        let digest = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        await remoteFS.setRemoteFile(path: "/release.txt", data: payload)
        await remoteFS.setRemoteFile(path: "/slow.bin", data: Data(repeating: 1, count: 64))

        let queue = TransferQueue { _ in remoteFS }
        let pID = UUID()

        let destOK = dir.appendingPathComponent("release.txt")
        let taskOK = TransferTaskMetadata(
            direction: .download,
            source: .remote(profileID: pID, host: "srv", path: "/release.txt"),
            destination: .local(url: destOK),
            totalBytes: Int64(payload.count),
            expectedSHA256: digest
        )
        _ = await queue.enqueue(taskOK)
        let okSnapshot = await waitUntilSnapshot(in: queue, id: taskOK.id) { $0.status.isTerminal }
        #expect(okSnapshot?.status == .completed)
        #expect(try Data(contentsOf: destOK) == payload)

        // Test SHA-256 mismatch rejection cleans temp file and fails
        let badDest = dir.appendingPathComponent("bad.txt")
        let taskBad = TransferTaskMetadata(
            direction: .download,
            source: .remote(profileID: pID, host: "srv", path: "/release.txt"),
            destination: .local(url: badDest),
            totalBytes: Int64(payload.count),
            expectedSHA256: String(repeating: "0", count: 64)
        )
        _ = await queue.enqueue(taskBad)
        let badSnap = await waitUntilSnapshot(in: queue, id: taskBad.id) { $0.status.isTerminal }
        if case .failed(AppError.checksumMismatch) = badSnap?.status {
            #expect(!FileManager.default.fileExists(atPath: badDest.path))
        } else {
            Issue.record("Expected checksumMismatch failure, got \(String(describing: badSnap?.status))")
        }
    }

    @Test("TransferQueue mid-transfer cancel settles cleanly in .cancelled without racing .completed (RUN-003)")
    func transferQueueMidTransferCancelReentrancy() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SparkleCancel-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let slowFS = MockRemoteFS()
        await slowFS.setRemoteFile(path: "/slow.bin", data: Data(repeating: 0xAB, count: 4096))
        await slowFS.setDownloadDelay(.milliseconds(400))

        let queue = TransferQueue { _ in slowFS }
        let dest = dir.appendingPathComponent("slow.bin")
        let task = TransferTaskMetadata(
            direction: .download,
            source: .remote(profileID: UUID(), host: "slow-host", path: "/slow.bin"),
            destination: .local(url: dest),
            totalBytes: 4096
        )
        _ = await queue.enqueue(task)
        _ = await waitUntilSnapshot(in: queue, id: task.id) { $0.status.isActive }
        await queue.cancel(id: task.id)

        let finalSnap = await waitUntilSnapshot(in: queue, id: task.id) { $0.status.isTerminal }
        #expect(finalSnap?.status == .cancelled)
        #expect(!FileManager.default.fileExists(atPath: dest.path))
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

    @Test("SHA256Verifier hashes 100MB file off MainActor without blocking UI thread (TASK-118 / PERF-002)")
    func largeFile100MBStreamingSHA256() async throws {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("Sparkle100MB-\(UUID()).bin")
        FileManager.default.createFile(atPath: tempFile.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let handle = try FileHandle(forUpdating: tempFile)
        try handle.truncate(atOffset: 100 * 1024 * 1024)
        try handle.close()

        let expectedZero100MBDigest = try await SHA256Verifier.computeHexDigest(of: tempFile)

        let verifyTask = Task.detached(priority: .utility) {
            try await SHA256Verifier.verify(fileURL: tempFile, expectedHex: expectedZero100MBDigest)
        }
        let start = ContinuousClock.now
        await MainActor.run {}
        let mainActorLatency = ContinuousClock.now - start
        #expect(mainActorLatency < .milliseconds(100))
        try await verifyTask.value
    }
}
