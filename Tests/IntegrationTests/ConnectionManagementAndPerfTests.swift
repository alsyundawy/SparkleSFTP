import Foundation
import NIOPosix
import SparkleCore
@testable import SparkleDesignSystem
@testable import SparkleFeatures
@testable import SparkleFileManager
@testable import SparkleNetworking
@testable import SparklePersistence
@testable import SparkleTerminal
@testable import SparkleTransferEngine
import Testing

private actor EphemeralCredentialStore: CredentialStoreProtocol {
    private var storage: [String: Data] = [:]

    func saveSecret(_ data: Data, for reference: SecretReference, requireTouchID _: Bool) async throws {
        storage[reference.accountKey] = data
    }

    func loadSecret(for reference: SecretReference, prompt _: String?) async throws -> Data {
        guard let data = storage[reference.accountKey] else {
            throw AppError.keychainFailure(status: -25300, message: "Not found")
        }
        return data
    }

    func deleteSecret(for reference: SecretReference) async throws {
        storage.removeValue(forKey: reference.accountKey)
    }

    func hasSecret(for reference: SecretReference) async -> Bool {
        storage[reference.accountKey] != nil
    }
}

private actor CountingTransferJournal: TransferJournalProtocol {
    private(set) var upsertCount = 0
    private var records: [UUID: TransferJournalRecord] = [:]

    func upsert(_ record: TransferJournalRecord) async throws {
        upsertCount += 1
        records[record.id] = record
    }

    func fetchAll() async throws -> [TransferJournalRecord] {
        Array(records.values)
    }

    func reconcileInterruptedOnLaunch() async throws -> [TransferJournalRecord] {
        []
    }

    func pruneOldEntries(maxEntries _: Int, maxAgeDays _: Int) async throws {}

    func delete(id: UUID) async throws {
        records.removeValue(forKey: id)
    }
}

@Suite("Connection Management, Performance & Fast Exit Tests")
struct ConnectionManagementAndPerfTests {
    @Test("Cloning connection duplicates Keychain references independently and multi-delete removes selection")
    @MainActor
    func cloneAndBatchDeleteProfiles() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SparkleConnPerf-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = ConnectionStore(fileURL: dir.appendingPathComponent("conn.json"))
        let creds = EphemeralCredentialStore()
        let snippets = CommandSnippetStore(fileURL: dir.appendingPathComponent("snippets.json"))
        let appState = AppState(
            credentialStore: creds,
            connectionStore: store,
            transferJournal: nil,
            snippetStore: snippets
        )

        let original = ConnectionProfile(
            name: "Prod Web",
            protocolType: .sftp,
            host: "web.example.com",
            port: 2222,
            username: "deploy",
            defaultRemotePath: "/var/www",
            defaultLocalPath: "/tmp",
            isFavorite: true
        )
        await appState.saveProfile(original, secretString: "top-secret-pass", passphraseString: nil)
        #expect(appState.profiles.count == 1)
        let savedOriginal = try #require(appState.profiles.first)
        let origPassRef = try #require(savedOriginal.passwordRef)

        let cloned = try #require(await appState.cloneProfile(savedOriginal))
        #expect(cloned.id != savedOriginal.id)
        #expect(cloned.host == "web.example.com")
        #expect(cloned.port == 2222)
        #expect(cloned.passwordRef != nil)
        #expect(cloned.passwordRef != origPassRef)

        if let clonedRef = cloned.passwordRef {
            let copiedBytes = try await creds.loadSecret(for: clonedRef, prompt: nil)
            #expect(String(data: copiedBytes, encoding: .utf8) == "top-secret-pass")
        }

        // Deleting clone leaves original secret intact
        await appState.deleteProfile(cloned)
        #expect(appState.profiles.count == 1)
        #expect(await creds.hasSecret(for: origPassRef) == true)

        // Clone twice, then Select All + batch Delete Selected
        _ = await appState.cloneProfile(savedOriginal)
        #expect(appState.profiles.count == 2)
        appState.selectAllVisibleProfiles()
        #expect(appState.selectedProfileIDs.count == 2)
        await appState.deleteProfiles(ids: appState.selectedProfileIDs)
        #expect(appState.profiles.isEmpty)
        #expect(await creds.hasSecret(for: origPassRef) == false)
    }

    @Test("ConnectionEditorMode and ConnectionAdvancedOptions preserve distinct edit identities and fields")
    @MainActor
    func editorModeAndFastShutdownPerf() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SparkleEditorMode-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let groupID = UUID()
        let existing = ConnectionProfile(
            name: "Bastion DB",
            groupID: groupID,
            protocolType: .sftp,
            host: "10.1.2.3",
            port: 2202,
            username: "admin",
            proxy: ProxyConfiguration(kind: .socks5, host: "127.0.0.1", port: 9050),
            defaultRemotePath: "/srv/data",
            defaultLocalPath: "/tmp/local",
            isFavorite: true
        )
        let createMode = ConnectionEditorMode.create
        let editMode = ConnectionEditorMode.edit(existing)
        #expect(createMode.id != editMode.id)

        let opts = ConnectionAdvancedOptions(profile: existing)
        #expect(opts.groupID == groupID)
        #expect(opts.defaultLocalPath == "/tmp/local")
        #expect(opts.proxyKind == .socks5)
        #expect(opts.proxyHost == "127.0.0.1")
        #expect(opts.proxyPort == "9050")

        // Cached palette/strings stay accurate across switches & fast shutdown stays non-blocking
        let appState = AppState(
            credentialStore: EphemeralCredentialStore(),
            connectionStore: ConnectionStore(fileURL: dir.appendingPathComponent("conn.json")),
            transferJournal: nil,
            snippetStore: CommandSnippetStore(fileURL: dir.appendingPathComponent("snippets.json"))
        )
        appState.selectLocale(code: "id")
        #expect(appState.strings.t("conn.cloneConnection") == "Duplikat Koneksi")
        #expect(appState.strings.t("conn.selectAll") == "Pilih Semua")

        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let clock = ContinuousClock()
        let elapsed = await clock.measure {
            appState.prepareFastShutdown()
            await appState.shutdownAsyncResources()
            await SSHClientService.closeChannelAndShutdownGroup(nil, group: group)
        }
        #expect(elapsed < .milliseconds(500))
    }

    @Test("TransferQueue throttles rapid journal checkpoints while LocalFileService reads POSIX stats")
    func transferJournalThrottleAndLocalLstat() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SparkleLstat-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let sampleFile = dir.appendingPathComponent("notes.txt")
        try Data("hello-lstat".utf8).write(to: sampleFile)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: sampleFile.path)

        let linkURL = dir.appendingPathComponent("notes-link.txt")
        try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: sampleFile)

        let entries = try await LocalFileService().listDirectory(at: dir)
        let regular = try #require(entries.first { $0.name == "notes.txt" })
        #expect(regular.size == 11)
        #expect(regular.permissions == 0o640)
        #expect(!regular.isDirectory)
        #expect(!regular.isSymlink)

        let symlink = try #require(entries.first { $0.name == "notes-link.txt" })
        #expect(symlink.isSymlink)

        let journal = CountingTransferJournal()
        let queue = TransferQueue(journal: journal) { _ in
            throw AppError.notConnected
        }
        let id = UUID()
        let meta = TransferTaskMetadata(
            id: id,
            direction: .upload,
            source: .local(url: sampleFile),
            destination: .remote(profileID: UUID(), host: "example.com", path: "/notes.txt"),
            totalBytes: 100
        )
        let zeroProgress = TransferProgress(bytesTransferred: 0, totalBytes: 100, bytesPerSecond: 0)
        await queue.recordSeedSnapshotForTest(
            TransferSnapshot(metadata: meta, status: .transferring(bytesPerSecond: 0), progress: zeroProgress)
        )
        for step in Int64(1) ... 5 {
            await queue.updateSnapshot(
                id: id,
                status: .transferring(bytesPerSecond: step * 100),
                progress: TransferProgress(bytesTransferred: step * 10, totalBytes: 100, bytesPerSecond: step * 100)
            )
        }
        // Only the first tick within the 2s checkpoint window triggers a SQLite upsert
        #expect(await journal.upsertCount == 1)

        await queue.updateSnapshot(
            id: id,
            status: .completed,
            progress: TransferProgress(bytesTransferred: 100, totalBytes: 100, bytesPerSecond: 100)
        )
        #expect(await journal.upsertCount == 2)
    }
}
