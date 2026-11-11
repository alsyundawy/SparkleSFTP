import Foundation
import SparkleCore
@testable import SparkleDesignSystem
@testable import SparkleFeatures
@testable import SparklePersistence
@testable import SparkleSynchronization
@testable import SparkleTerminal
@testable import SparkleTransferEngine
import Testing

@Suite("Notepad2 Editor, Theme/i18n State & Bidirectional Executor Tests")
struct EditorAndSyncTests {
    @Test("Editor models handle BOM encoding, LF/CRLF normalization, cursor, regex find/replace, and transforms")
    func editorCoreModelOperations() {
        let text = "b line  \na line\nC Line\t"
        let trimmed = EditorTextTransformKind.apply(.trimTrailingWhitespace, to: text)
        #expect(trimmed == "b line\na line\nC Line")

        let sorted = EditorTextTransformKind.apply(.sortLinesAscending, to: trimmed)
        #expect(sorted == "a line\nb line\nC Line")

        let crlf = EditorLineEnding.normalize(sorted, to: .windowsCRLF)
        #expect(EditorLineEnding.detect(in: crlf) == .windowsCRLF)

        let bomEncoded = EditorTextEncoding.utf8BOM.encode("hello")
        let decoded = EditorTextEncoding.decode(bomEncoded)
        #expect(decoded.encoding == .utf8BOM)
        #expect(decoded.text == "hello")

        let cursor = EditorCursorLocation.locate(in: "one\ntwo\nthree", utf16Offset: 6)
        #expect(cursor == EditorCursorLocation(line: 2, column: 3))

        let regexQuery = EditorFindQuery(searchText: "line", matchCase: false, useRegex: true)
        #expect(regexQuery.matchRanges(in: trimmed).count == 3)
    }

    @Test("EditorSessionManager opens local/remote docs and performs replaceAll cleanly")
    @MainActor
    func editorSessionManagerOperations() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SparkleEditor-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = dir.appendingPathComponent("sample.conf")
        try Data("host=alpha\nhost=alpha\n".utf8).write(to: fileURL)

        let manager = EditorSessionManager()
        try manager.openLocalFile(at: fileURL)
        #expect(manager.documents.count == 1)
        manager.findQuery = EditorFindQuery(searchText: "alpha", replaceText: "beta")
        let replaced = manager.replaceAllMatches()
        #expect(replaced == 2)
        #expect(manager.activeDocument?.content.contains("host=beta") == true)
        #expect(manager.activeDocument?.isDirty == true)
    }

    @Test("AppState switches SparkNotePad themes, locales, update state, and commits FileZilla imports")
    @MainActor
    func appStateThemesLocalesAndImports() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SparkleState2-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = ConnectionStore(fileURL: dir.appendingPathComponent("conn.json"))
        let snippets = CommandSnippetStore(fileURL: dir.appendingPathComponent("snippets.json"))
        let appState = AppState(
            connectionStore: store,
            transferJournal: nil,
            snippetStore: snippets,
            performUpdateCheckAction: { _, _ in .updateAvailable(
                version: "0.4.0",
                releaseURL: URL(string: "https://github.com/alsyundawy/SparkleSFTP/releases/tag/v0.4.0")!,
                notes: "New release"
            ) }
        )

        if let tokyo = appState.availableThemes.first(where: { $0.id == "tokyoNight" }) {
            appState.selectTheme(tokyo)
            #expect(appState.activePalette.id == "tokyoNight")
        }
        appState.selectLocale(code: "id")
        #expect(appState.strings.connect == "Hubungkan")

        await appState.checkForUpdates(manual: true)
        if case let .updateAvailable(version, _, _) = appState.autoUpdateStatus {
            #expect(version == "0.4.0")
        } else {
            Issue.record("Expected updateAvailable status")
        }

        let imported = [
            ImportedConnection(
                profile: ConnectionProfile(name: "Box", protocolType: .sftp, host: "box.local", username: "dev"),
                groupName: "Work"
            )
        ]
        await appState.commitImportedConnections(imported, createGroups: true, skipDuplicates: true)
        await appState.commitImportedConnections(imported, createGroups: true, skipDuplicates: true)
        #expect(appState.profiles.count == 1)
        #expect(appState.groups.contains { $0.name == "Work" })
    }

    @Test("SyncExecutor executes bidirectional uploads and remote-to-local downloads safely")
    func syncExecutorBidirectionalExecution() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SparkleBiSync-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try Data("from-local".utf8).write(to: dir.appendingPathComponent("upload.txt"))

        let remoteData = Data("from-remote".utf8)
        let remoteMock = BidirectionalMockRemoteFS(files: ["/sync/download.txt": remoteData])
        let queue = TransferQueue(maxGlobalConcurrent: 2, maxPerHostConcurrent: 2, journal: nil) { _ in remoteMock }

        let plan = SyncPlan(
            direction: .bidirectional,
            actions: [
                SyncAction(
                    relativePath: "upload.txt",
                    kind: .create,
                    transferDirection: .upload,
                    isDirectory: false,
                    size: 10
                ),
                SyncAction(
                    relativePath: "download.txt",
                    kind: .create,
                    transferDirection: .download,
                    isDirectory: false,
                    size: Int64(remoteData.count)
                )
            ]
        )
        let target = SyncExecutionTarget(
            localRoot: dir,
            remoteRoot: "/sync",
            profileID: UUID(),
            host: "bi.example.com",
            remoteFS: remoteMock
        )
        let executor = SyncExecutor(transferQueue: queue)
        let report = try await executor.execute(plan: plan, target: target, dryRun: false)
        #expect(report.appliedCount == 2)
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            let snaps = await queue.currentSnapshots()
            if snaps.count == 2, snaps.allSatisfy(\.status.isTerminal) {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        let uploaded = await remoteMock.files["/sync/upload.txt"]
        #expect(uploaded == Data("from-local".utf8))
        let downloaded = try Data(contentsOf: dir.appendingPathComponent("download.txt"))
        #expect(downloaded == remoteData)
    }
}

private actor BidirectionalMockRemoteFS: RemoteFileSystem {
    var files: [String: Data]

    init(files: [String: Data]) {
        self.files = files
    }

    func listDirectory(at _: RemotePath) async throws -> [RemoteFile] {
        []
    }

    func metadata(at path: RemotePath) async throws -> RemoteFileMetadata {
        guard let data = files[path.rawValue] else { throw AppError.fileNotFound(path: path.rawValue) }
        return RemoteFileMetadata(path: path, size: Int64(data.count), isDirectory: false)
    }

    func resolveSymlink(at path: RemotePath) async throws -> RemotePath {
        path
    }

    func download(
        from remotePath: RemotePath,
        to localURL: URL,
        offset _: Int64,
        onProgress: @escaping @Sendable (TransferProgress) -> Void
    ) async throws {
        guard let data = files[remotePath.rawValue] else { throw AppError.fileNotFound(path: remotePath.rawValue) }
        try data.write(to: localURL, options: [.atomic])
        onProgress(TransferProgress(
            bytesTransferred: Int64(data.count),
            totalBytes: Int64(data.count),
            bytesPerSecond: 1024
        ))
    }

    func upload(
        from localURL: URL,
        to remotePath: RemotePath,
        offset _: Int64,
        onProgress: @escaping @Sendable (TransferProgress) -> Void
    ) async throws {
        let data = try Data(contentsOf: localURL)
        files[remotePath.rawValue] = data
        onProgress(TransferProgress(
            bytesTransferred: Int64(data.count),
            totalBytes: Int64(data.count),
            bytesPerSecond: 1024
        ))
    }

    func delete(at path: RemotePath, isDirectory _: Bool) async throws {
        files.removeValue(forKey: path.rawValue)
    }

    func rename(from source: RemotePath, to destination: RemotePath) async throws {
        files[destination.rawValue] = files.removeValue(forKey: source.rawValue)
    }

    func createDirectory(at _: RemotePath) async throws {}
    func setPermissions(_: UInt32, at _: RemotePath) async throws {}
}
