import Foundation
import SparkleCore
@testable import SparkleFileManager
@testable import SparklePersistence
@testable import SparkleSecurity
@testable import SparkleSynchronization
@testable import SparkleTerminal
@testable import SparkleTransferEngine
import Testing

actor InMemorySyncRemoteFS: RemoteFileSystem {
    var uploaded: [String: Data] = [:]
    var remoteEntries: [RemoteFile] = []

    func listDirectory(at path: RemotePath) async throws -> [RemoteFile] {
        remoteEntries
    }

    func metadata(at path: RemotePath) async throws -> RemoteFileMetadata {
        guard let data = uploaded[path.rawValue] else {
            throw AppError.fileNotFound(path: path.rawValue)
        }
        return RemoteFileMetadata(path: path, size: Int64(data.count), isDirectory: false)
    }

    func resolveSymlink(at path: RemotePath) async throws -> RemotePath { path }

    func download(
        from remotePath: RemotePath,
        to localURL: URL,
        offset: Int64,
        onProgress: @escaping @Sendable (TransferProgress) -> Void
    ) async throws {}

    func upload(
        from localURL: URL,
        to remotePath: RemotePath,
        offset: Int64,
        onProgress: @escaping @Sendable (TransferProgress) -> Void
    ) async throws {
        let data = try Data(contentsOf: localURL)
        uploaded[remotePath.rawValue] = data
        let progress = TransferProgress(
            bytesTransferred: Int64(data.count),
            totalBytes: Int64(data.count),
            bytesPerSecond: 1024
        )
        onProgress(progress)
    }

    func delete(at path: RemotePath, isDirectory: Bool) async throws {
        uploaded.removeValue(forKey: path.rawValue)
    }

    func rename(from source: RemotePath, to destination: RemotePath) async throws {
        guard let data = uploaded.removeValue(forKey: source.rawValue) else {
            throw AppError.fileNotFound(path: source.rawValue)
        }
        uploaded[destination.rawValue] = data
    }

    func createDirectory(at path: RemotePath) async throws {}
    func setPermissions(_ permissions: UInt32, at path: RemotePath) async throws {}
}

@Suite("SparkleSFTP End-to-End Integration Tests")
struct IntegrationTests {
    @Test("End-to-end sync -> TransferQueue -> TransferJournal -> LocalFileService round trip")
    func endToEndLocalToRemoteSyncAndJournal() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SparkleE2E-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let localPayload = Data("Production Config v1".utf8)
        let localFile = dir.appendingPathComponent("app.conf")
        try localPayload.write(to: localFile)

        let journal = try TransferJournal(databaseURL: dir.appendingPathComponent("journal.sqlite3"))
        let remoteFS = InMemorySyncRemoteFS()
        let profileID = UUID()

        let queue = TransferQueue(
            maxGlobalConcurrent: 2,
            maxPerHostConcurrent: 2,
            journal: journal
        ) { _ in remoteFS }

        let scannedLocal = try await DirectoryScanner.scanLocal(rootURL: dir)
            .filter { $0.relativePath == "app.conf" }
        let plan = SyncPlanner.buildPlan(source: scannedLocal, destination: [])
        let executor = SyncExecutor(transferQueue: queue)
        let target = SyncExecutionTarget(
            localRoot: dir,
            remoteRoot: "/etc/sparklesftp",
            profileID: profileID,
            host: "10.0.0.5",
            remoteFS: remoteFS
        )
        let report = try await executor.execute(plan: plan, target: target, dryRun: false)
        #expect(report.appliedCount == 1)
        try await Task.sleep(for: .milliseconds(250))

        let uploadedData = await remoteFS.uploaded["/etc/sparklesftp/app.conf"]
        #expect(uploadedData == localPayload)

        let journalRows = try await journal.fetchAll()
        #expect(journalRows.count == 1)
        #expect(journalRows.first?.statusCode == "completed")
    }

    @Test("TerminalSessionManager opens and closes 100 tabs cleanly without retaining sessions (MEM-002)")
    @MainActor
    func hundredTerminalTabsTeardown() async throws {
        let manager = TerminalSessionManager()
        for idx in 0 ..< 100 {
            let tab = try await manager.openSession(title: "Tab \(idx)", sshClient: nil)
            manager.closeSession(id: tab.id)
        }
        #expect(manager.sessions.isEmpty)
        #expect(manager.selectedSessionID == nil)
    }
}
