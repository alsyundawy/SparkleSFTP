import Foundation
import SparkleCore
@testable import SparkleFeatures
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

    func listDirectory(at _: RemotePath) async throws -> [RemoteFile] {
        remoteEntries
    }

    func metadata(at path: RemotePath) async throws -> RemoteFileMetadata {
        guard let data = uploaded[path.rawValue] else {
            throw AppError.fileNotFound(path: path.rawValue)
        }
        return RemoteFileMetadata(path: path, size: Int64(data.count), isDirectory: false)
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
        let data = try Data(contentsOf: localURL)
        uploaded[remotePath.rawValue] = data
        let progress = TransferProgress(
            bytesTransferred: Int64(data.count),
            totalBytes: Int64(data.count),
            bytesPerSecond: 1024
        )
        onProgress(progress)
    }

    func delete(at path: RemotePath, isDirectory _: Bool) async throws {
        uploaded.removeValue(forKey: path.rawValue)
    }

    func rename(from source: RemotePath, to destination: RemotePath) async throws {
        guard let data = uploaded.removeValue(forKey: source.rawValue) else {
            throw AppError.fileNotFound(path: source.rawValue)
        }
        uploaded[destination.rawValue] = data
    }

    func createDirectory(at _: RemotePath) async throws {}
    func setPermissions(_: UInt32, at _: RemotePath) async throws {}
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
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            let snaps = await queue.currentSnapshots()
            if let snap = snaps.first, snap.status.isTerminal {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }

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

    @Test("AppState manages groups, pane back/forward navigation, and custom snippets cleanly")
    @MainActor
    func appStateNavigationGroupsAndSnippets() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SparkleState-\(UUID())")
        let subA = dir.appendingPathComponent("folderA", isDirectory: true)
        let subB = dir.appendingPathComponent("folderB", isDirectory: true)
        try FileManager.default.createDirectory(at: subA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: subB, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = ConnectionStore(fileURL: dir.appendingPathComponent("conn.json"))
        let snippetStore = CommandSnippetStore(fileURL: dir.appendingPathComponent("snippets.json"))
        let appState = AppState(
            connectionStore: store,
            transferJournal: nil,
            snippetStore: snippetStore
        )

        await appState.createGroup(named: "Production")
        #expect(appState.groups.count == 1)
        if let groupID = appState.groups.first?.id {
            await appState.deleteGroup(id: groupID)
            #expect(appState.groups.isEmpty)
        }

        await appState.refreshLocalDirectory(dir, recordHistory: false)
        appState.localHistory = PaneNavigationHistory(initialPath: dir.path)
        await appState.refreshLocalDirectory(subA)
        await appState.refreshLocalDirectory(subB)
        #expect(appState.localCurrentURL.standardizedFileURL == subB.standardizedFileURL)

        await appState.goBackInActivePane()
        #expect(appState.localCurrentURL.standardizedFileURL == subA.standardizedFileURL)
        await appState.goForwardInActivePane()
        #expect(appState.localCurrentURL.standardizedFileURL == subB.standardizedFileURL)

        let baselineCount = appState.snippets.count
        await appState.addSnippet(title: "Tail Nginx", command: "tail -f /var/log/nginx/error.log")
        #expect(appState.snippets.count == baselineCount + 1)
        let loaded = try await snippetStore.loadSnippets()
        #expect(loaded.contains { $0.title == "Tail Nginx" })
    }
}
