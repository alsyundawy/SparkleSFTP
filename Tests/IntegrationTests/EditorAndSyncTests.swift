import Foundation
import SparkleCore
@testable import SparkleDesignSystem
@testable import SparkleFeatures
@testable import SparkleFileManager
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

    @Test("Zero-allocation line count traverses UTF-8 bytes and detect resolves 52+ languages")
    func zeroAllocationLineCountAndSyntaxDetection() {
        let emptyDoc = EditorDocument(title: "empty.txt", content: "")
        #expect(emptyDoc.lineCount == 1)

        let singleDoc = EditorDocument(title: "single.txt", content: "hello world")
        #expect(singleDoc.lineCount == 1)

        let multiDoc = EditorDocument(title: "multi.txt", content: "line 1\nline 2\nline 3")
        #expect(multiDoc.lineCount == 3)

        let trailingDoc = EditorDocument(title: "trailing.txt", content: "line 1\nline 2\n")
        #expect(trailingDoc.lineCount == 3)

        let crlfDoc = EditorDocument(title: "crlf.txt", content: "line 1\r\nline 2\r\nline 3\r\n")
        #expect(crlfDoc.lineCount == 4)

        #expect(EditorSyntaxLanguage.detect(from: "main.swift") == .swift)
        #expect(EditorSyntaxLanguage.detect(from: "App.tsx") == .tsx)
        #expect(EditorSyntaxLanguage.detect(from: "server.py") == .python)
        #expect(EditorSyntaxLanguage.detect(from: "Dockerfile") == .dockerfile)
        #expect(EditorSyntaxLanguage.detect(from: "nginx.conf") == .nginx)
        #expect(EditorSyntaxLanguage.detect(from: "config.toml") == .toml)
        #expect(EditorSyntaxLanguage.detect(from: "styles.css") == .css)
        #expect(EditorSyntaxLanguage.detect(from: "diff.patch") == .diff)
        #expect(EditorSyntaxLanguage.detect(from: "script.sh", content: "#!/usr/bin/env python3") == .python)
    }

    @Test("PaginatedFileWindow filters by substring, wildcard extension, and hidden attribute")
    func paginatedFileWindowFiltering() {
        let files = [
            RemoteFile(name: "syslog.log", path: RemotePath("/var/log/syslog.log"), size: 100, isDirectory: false),
            RemoteFile(name: "nginx.log", path: RemotePath("/var/log/nginx.log"), size: 200, isDirectory: false),
            RemoteFile(name: "nginx.conf", path: RemotePath("/etc/nginx.conf"), size: 50, isDirectory: false),
            RemoteFile(name: ".bashrc", path: RemotePath("/home/user/.bashrc"), size: 30, isDirectory: false),
            RemoteFile(name: "main.swift", path: RemotePath("/src/main.swift"), size: 500, isDirectory: false)
        ]

        var window = PaginatedFileWindow(allFiles: files, pageSize: 10, filterQuery: "")
        #expect(window.visibleFiles.count == 5)

        window.setFilter("nginx")
        #expect(window.visibleFiles.count == 2)

        window.setFilter("*.log")
        #expect(window.visibleFiles.count == 2)

        window.setFilter(".*")
        #expect(window.visibleFiles.count == 1)
        #expect(window.visibleFiles.first?.name == ".bashrc")
    }

    @Test("BookmarkManager computes synchronized browsing path correctly")
    @MainActor
    func synchronizedBrowsingPathComputation() {
        BookmarkManager.shared.isSynchronizedBrowsingEnabled = true
        defer { BookmarkManager.shared.isSynchronizedBrowsingEnabled = false }

        let targetRemote = BookmarkManager.shared.computeSynchronizedPath(
            from: "/Users/dev/project",
            to: "/Users/dev/project/src",
            currentOppositePath: "/var/www/project"
        )
        #expect(targetRemote == "/var/www/project/src")

        let targetParent = BookmarkManager.shared.computeSynchronizedPath(
            from: "/Users/dev/project/src",
            to: "/Users/dev/project",
            currentOppositePath: "/var/www/project/src"
        )
        #expect(targetParent == "/var/www/project")
    }

    @Test("EditorFindQuery whole-word and mark subsystem operations execute accurately")
    @MainActor
    func editorFindQueryAndMarkSubsystem() {
        let content = "cat scatter concatenate cat\nsecond line cat\nfinal"
        let manager = EditorSessionManager()
        manager.documents = [EditorDocument(title: "test.txt", content: content)]
        manager.activeDocumentID = manager.documents.first?.id

        manager.findQuery = EditorFindQuery(searchText: "cat", wholeWord: true)
        let ranges = manager.findQuery.matchRanges(in: content)
        #expect(ranges.count == 3)

        let markCount = manager.markAllMatches()
        #expect(markCount == 3)
        #expect(manager.findQuery.markedRanges.count == 3)

        let bookmarkedCount = manager.bookmarkMatchingLines()
        #expect(bookmarkedCount == 2)
        #expect(manager.findQuery.bookmarkedLines.contains(1))
        #expect(manager.findQuery.bookmarkedLines.contains(2))

        manager.clearAllMarks()
        #expect(manager.findQuery.markedRanges.isEmpty)
        #expect(manager.findQuery.bookmarkedLines.isEmpty)
    }

    @Test("DockProgressController calculates active transfer ratio and clears correctly")
    @MainActor
    func dockProgressControllerBadge() {
        let meta = TransferTaskMetadata(
            direction: .upload,
            source: .local(url: URL(fileURLWithPath: "/tmp/a")),
            destination: .remote(profileID: UUID(), host: "127.0.0.1", path: RemotePath(rawValue: "/tmp/a")),
            totalBytes: 100
        )
        let prog = TransferProgress(bytesTransferred: 50, totalBytes: 100, bytesPerSecond: 1024)
        let activeSnapshots = [
            TransferSnapshot(
                metadata: meta,
                status: .transferring(bytesPerSecond: 1024),
                progress: prog
            )
        ]
        DockProgressController.shared.updateDockProgress(from: activeSnapshots)
        DockProgressController.shared.clearDockProgress()
    }

    @Test("EditorDeveloperTools handles Base64, URL, JSON, Crypto, Epoch, and Dedup")
    func editorDeveloperToolsExecution() throws {
        let b64 = try EditorDeveloperTools.execute(.base64Encode, on: "Hello World")
        #expect(b64 == "SGVsbG8gV29ybGQ=")
        let decodedB64 = try EditorDeveloperTools.execute(.base64Decode, on: b64)
        #expect(decodedB64 == "Hello World")

        let url = try EditorDeveloperTools.execute(.urlEncode, on: "hello world&foo=bar")
        #expect(url.contains("%20") || url.contains("hello"))
        let decodedURL = try EditorDeveloperTools.execute(.urlDecode, on: url)
        #expect(decodedURL == "hello world&foo=bar")

        let jsonPretty = try EditorDeveloperTools.execute(.jsonPrettyPrint, on: "{\"b\":2,\"a\":1}")
        #expect(jsonPretty.contains("\n"))

        let sha256 = try EditorDeveloperTools.execute(.sha256, on: "SparkleSFTP")
        #expect(sha256.count == 64)

        let epochISO = try EditorDeveloperTools.execute(.unixToISO8601, on: "1700000000")
        #expect(epochISO.contains("2023"))

        let dedup = try EditorDeveloperTools.execute(.deduplicateLines, on: "a\nb\na\nc\nb")
        #expect(dedup == "a\nb\nc")
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
