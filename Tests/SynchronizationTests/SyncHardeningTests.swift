import Foundation
import SparkleCore
@testable import SparkleSynchronization
@testable import SparkleTransferEngine
import Testing

private actor SyncMockRemoteFS: RemoteFileSystem {
    var mtimes: [String: Date] = [:]
    var contents: [String: Data] = [:]

    func seed(path: String, data: Data, mtime: Date) {
        contents[path] = data
        mtimes[path] = mtime
    }

    func listDirectory(at _: RemotePath) async throws -> [RemoteFile] {
        []
    }

    func metadata(at path: RemotePath) async throws -> RemoteFileMetadata {
        guard let data = contents[path.rawValue] else {
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
        offset _: Int64,
        onProgress _: @escaping @Sendable (TransferProgress) -> Void
    ) async throws {
        guard let data = contents[remotePath.rawValue] else {
            throw AppError.fileNotFound(path: remotePath.rawValue)
        }
        try data.write(to: localURL, options: [.atomic])
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

@Suite("Synchronization Hardening Tests")
struct SyncHardeningTests {
    @Test("SyncPlanner handles duplicate paths and remoteToLocal updates without false conflict")
    func remoteToLocalUpdateMatchesRemoteMtime() async throws {
        let localTime = Date(timeIntervalSince1970: 1_700_000_000)
        let remoteTime = Date(timeIntervalSince1970: 1_700_005_000)
        let local = [
            ScannedFileEntry(relativePath: "app.conf", size: 5, modificationTime: localTime, isDirectory: false),
            ScannedFileEntry(relativePath: "app.conf", size: 5, modificationTime: localTime, isDirectory: false)
        ]
        let remote = [
            ScannedFileEntry(relativePath: "app.conf", size: 12, modificationTime: remoteTime, isDirectory: false)
        ]

        let plan = SyncPlanner.buildPlan(
            source: local,
            destination: remote,
            direction: .remoteToLocal,
            mode: .sizeAndMtime,
            deleteExtras: false,
            now: remoteTime
        )
        let update = try #require(plan.updateActions.first)
        #expect(update.transferDirection == .download)
        #expect(update.expectedMtime == remoteTime)

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SparkleSyncExec-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let remoteFS = SyncMockRemoteFS()
        await remoteFS.seed(path: "/srv/app.conf", data: Data("updated-conf".utf8), mtime: remoteTime)
        let queue = TransferQueue { _ in remoteFS }
        let executor = SyncExecutor(transferQueue: queue)
        let report = try await executor.execute(
            plan: plan,
            target: SyncExecutionTarget(
                localRoot: dir,
                remoteRoot: "/srv",
                profileID: UUID(),
                host: "srv",
                remoteFS: remoteFS
            ),
            dryRun: false,
            now: remoteTime
        )
        #expect(report.appliedCount == 1)
    }

    @Test("SyncExecutor rejects multi-segment local relative path traversal")
    func syncExecutorBlocksMultiSegmentTraversal() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SparkleSyncTrav-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let now = Date()
        let badPlan = SyncPlan(
            createdAt: now,
            expiresAt: now.addingTimeInterval(60),
            direction: .remoteToLocal,
            deleteExtras: false,
            actions: [
                SyncAction(
                    relativePath: "sub/../../escape.txt",
                    kind: .create,
                    transferDirection: .download,
                    isDirectory: false,
                    size: 4,
                    expectedMtime: now
                )
            ]
        )
        let remoteFS = SyncMockRemoteFS()
        let executor = SyncExecutor(transferQueue: TransferQueue { _ in remoteFS })
        var threwTraversal = false
        do {
            _ = try await executor.execute(
                plan: badPlan,
                target: SyncExecutionTarget(
                    localRoot: dir,
                    remoteRoot: "/srv",
                    profileID: UUID(),
                    host: "srv",
                    remoteFS: remoteFS
                ),
                dryRun: false,
                now: now
            )
        } catch AppError.pathTraversal {
            threwTraversal = true
        }
        #expect(threwTraversal)
    }
}
