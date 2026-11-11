import Foundation
import SparkleCore
@testable import SparkleTransferEngine
import Testing

private actor BatchQueueMockRemoteFS: RemoteFileSystem {
    var shouldFailNextUpload = true
    var uploadAttempts = 0
    private var storedSizes: [String: Int64] = [:]

    func listDirectory(at _: RemotePath) async throws -> [RemoteFile] {
        []
    }

    func metadata(at path: RemotePath) async throws -> RemoteFileMetadata {
        guard let size = storedSizes[path.rawValue] else {
            throw AppError.fileNotFound(path: path.rawValue)
        }
        return RemoteFileMetadata(path: path, size: size, isDirectory: false)
    }

    func resolveSymlink(at path: RemotePath) async throws -> RemotePath {
        path
    }

    func download(
        from _: RemotePath,
        to _: URL,
        offset _: Int64,
        onProgress _: @escaping @Sendable (TransferProgress) -> Void
    ) async throws {}

    func upload(
        from localURL: URL,
        to remotePath: RemotePath,
        offset _: Int64,
        onProgress: @escaping @Sendable (TransferProgress) -> Void
    ) async throws {
        uploadAttempts += 1
        if shouldFailNextUpload {
            shouldFailNextUpload = false
            throw AppError.permissionDenied(path: localURL.path)
        }
        let size = Int64((try? Data(contentsOf: localURL).count) ?? 0)
        storedSizes[remotePath.rawValue] = size
        onProgress(
            TransferProgress(
                bytesTransferred: size,
                totalBytes: size,
                bytesPerSecond: 1024
            )
        )
    }

    func delete(at path: RemotePath, isDirectory _: Bool) async throws {
        storedSizes.removeValue(forKey: path.rawValue)
    }

    func rename(from source: RemotePath, to destination: RemotePath) async throws {
        if let size = storedSizes.removeValue(forKey: source.rawValue) {
            storedSizes[destination.rawValue] = size
        }
    }

    func createDirectory(at _: RemotePath) async throws {}
    func setPermissions(_: UInt32, at _: RemotePath) async throws {}
}

@Suite("Independent Upload/Download 8-Policy Conflict & Queue Batch Tests")
struct TransferBatchAndPolicyTests {
    @Test("ConflictResolver enforces upload size/mtime policies independently of download policies")
    func independentUploadAndDownloadPoliciesSizeAndNewer() async {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let older = now.addingTimeInterval(-3600)
        let resolver = ConflictResolver(defaultPolicy: .overwriteIfDifferentSize, defaultDownloadPolicy: .skip)

        let sameUpload = await resolver.resolve(
            makeContext(.upload, existingSize: 100, incomingSize: 100, existingAt: older, incomingAt: now),
            originalFilename: "same.txt"
        )
        #expect(sameUpload == .skip)

        let diffUpload = await resolver.resolve(
            makeContext(.upload, existingSize: 100, incomingSize: 200, existingAt: now, incomingAt: older),
            originalFilename: "diff.txt"
        )
        #expect(diffUpload == .overwrite)

        let skippedDown = await resolver.resolve(
            makeContext(.download, existingSize: 100, incomingSize: 200, existingAt: older, incomingAt: now),
            originalFilename: "diff.txt"
        )
        #expect(skippedDown == .skip)

        await resolver.updateDefaultPolicies(upload: .overwriteIfDifferentSize, download: .overwriteIfNewer)
        let newerDown = await resolver.resolve(
            makeContext(.download, existingSize: 100, incomingSize: 100, existingAt: older, incomingAt: now),
            originalFilename: "newer.txt"
        )
        #expect(newerDown == .overwrite)
    }

    @Test("ConflictResolver supports overwriteIfDifferentSizeOrNewer, resume, rename, and overwrite")
    func remainingConflictPoliciesWorkIndependently() async {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let older = now.addingTimeInterval(-3600)
        let resolver = ConflictResolver(defaultPolicy: .overwriteIfDifferentSizeOrNewer, defaultDownloadPolicy: .resume)

        let sameUpload = await resolver.resolve(
            makeContext(.upload, existingSize: 100, incomingSize: 100, existingAt: now, incomingAt: older),
            originalFilename: "identical.txt"
        )
        #expect(sameUpload == .skip)

        let resumeDown = await resolver.resolve(
            makeContext(.download, existingSize: 200, incomingSize: 500, existingAt: older, incomingAt: now),
            originalFilename: "part.bin"
        )
        #expect(resumeDown == .resume)

        await resolver.updateDefaultPolicies(upload: .rename, download: .overwrite)
        let renamed = await resolver.resolve(
            makeContext(.upload, existingSize: 10, incomingSize: 10, existingAt: now, incomingAt: now),
            originalFilename: "dup.log"
        )
        if case let .rename(newName) = renamed {
            #expect(newName != "dup.log" && newName.hasSuffix(".log"))
        } else {
            Issue.record("Expected .rename conflict resolution")
        }

        let overwrote = await resolver.resolve(
            makeContext(.download, existingSize: 10, incomingSize: 10, existingAt: now, incomingAt: older),
            originalFilename: "any.bin"
        )
        #expect(overwrote == .overwrite)
    }

    @Test("TransferQueue supports enqueueBatch, retryAllFailed, clearCompleted, and cancelAll")
    func queueBatchRetryAndClearLifecycle() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SparkleBatch-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileA = dir.appendingPathComponent("a.txt")
        let fileB = dir.appendingPathComponent("b.txt")
        try Data("alpha".utf8).write(to: fileA)
        try Data("bravo".utf8).write(to: fileB)

        let remoteFS = BatchQueueMockRemoteFS()
        let queue = TransferQueue(
            maxGlobalConcurrent: 1,
            maxPerHostConcurrent: 1,
            conflictResolver: ConflictResolver(defaultPolicy: .overwrite)
        ) { _ in remoteFS }

        let metaA = TransferTaskMetadata(
            direction: .upload,
            source: .local(url: fileA),
            destination: .remote(profileID: UUID(), host: "srv", path: "/a.txt"),
            totalBytes: 5
        )
        let metaB = TransferTaskMetadata(
            direction: .upload,
            source: .local(url: fileB),
            destination: .remote(profileID: UUID(), host: "srv", path: "/b.txt"),
            totalBytes: 5
        )

        #expect(await queue.enqueueBatch([metaA, metaB]).count == 2)
        await waitUntil(in: queue) { $0.allSatisfy(\.status.isTerminal) }

        let firstPass = await queue.currentSnapshots()
        #expect(firstPass.contains { $0.id == metaA.id && $0.status.isFailed })
        #expect(firstPass.contains { $0.id == metaB.id && $0.status == .completed })

        await queue.retryAllFailed()
        await waitUntil(in: queue) { $0.allSatisfy { $0.status == .completed } }
        #expect(await queue.currentSnapshots().allSatisfy { $0.status == .completed })

        await queue.clearCompleted()
        #expect(await queue.currentSnapshots().isEmpty)
        await queue.cancelAll()
        #expect(await queue.currentSnapshots().isEmpty)
    }

    private func makeContext(
        _ direction: TransferDirection,
        existingSize: Int64,
        incomingSize: Int64,
        existingAt: Date,
        incomingAt: Date
    ) -> ConflictContext {
        ConflictContext(
            taskID: UUID(),
            direction: direction,
            destinationDisplayPath: "/item",
            existingSize: existingSize,
            incomingSize: incomingSize,
            existingModifiedAt: existingAt,
            incomingModifiedAt: incomingAt
        )
    }

    private func waitUntil(in queue: TransferQueue, predicate: @Sendable ([TransferSnapshot]) -> Bool) async {
        for _ in 0 ..< 100 {
            let snaps = await queue.currentSnapshots()
            if predicate(snaps) {
                return
            }
            try? await Task.sleep(for: .milliseconds(25))
        }
    }
}
