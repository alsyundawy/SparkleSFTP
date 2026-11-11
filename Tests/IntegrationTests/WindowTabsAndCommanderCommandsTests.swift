import Crypto
import Foundation
import NIOPosix
import NIOSSH
import SparkleCore
@testable import SparkleDesignSystem
@testable import SparkleFeatures
@testable import SparkleFileManager
@testable import SparkleNetworking
@testable import SparklePersistence
@testable import SparkleSecurity
@testable import SparkleTerminal
@testable import SparkleTransferEngine
import Testing

private actor EphemeralWindowCredStore: CredentialStoreProtocol {
    private var storage: [String: Data] = [:]

    func saveSecret(_ data: Data, for reference: SecretReference, requireTouchID _: Bool) async throws {
        storage[reference.accountKey] = data
    }

    func loadSecret(for reference: SecretReference, prompt _: String?) async throws -> Data {
        guard let data = storage[reference.accountKey] else {
            throw AppError.credentialNotFound(service: reference.accountKey)
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

private actor EphemeralTrustBacking: HostTrustBackingStore {
    private var blob: Data?
    func loadTrustBlob() async throws -> Data? {
        blob
    }

    func saveTrustBlob(_ data: Data) async throws {
        blob = data
    }
}

private struct LoopbackTestPaths: Sendable {
    let root: URL
    let remoteRoot: URL
    let localDirA: URL
    let localDirB: URL
    let port: Int

    static func createDirectories(prefix: String) throws -> LoopbackTestPaths {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("\(prefix)-\(UUID())")
        let remote = root.appendingPathComponent("remote", isDirectory: true)
        let localA = root.appendingPathComponent("localA", isDirectory: true)
        let localB = root.appendingPathComponent("localB", isDirectory: true)
        try FileManager.default.createDirectory(at: remote, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: localA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: localB, withIntermediateDirectories: true)
        return LoopbackTestPaths(root: root, remoteRoot: remote, localDirA: localA, localDirB: localB, port: 0)
    }

    func withPort(_ port: Int) -> LoopbackTestPaths {
        LoopbackTestPaths(root: root, remoteRoot: remoteRoot, localDirA: localDirA, localDirB: localDirB, port: port)
    }
}

@Suite("Multi-Window Isolation, Multi-Tab Sessions & Commander Commands Tests")
struct WindowTabsAndCommanderCommandsTests {
    @Test("Independent windows isolate activeSessions while supporting paired multi-tab host sessions")
    func independentWindowsAndMultiTabSessions() async throws {
        let dirs = try LoopbackTestPaths.createDirectories(prefix: "SparkleWin")
        defer { try? FileManager.default.removeItem(at: dirs.root) }

        let vfs = try LoopbackSFTPVirtualFS(rootURL: dirs.remoteRoot)
        let serverKey = NIOSSHPrivateKey(ed25519Key: Curve25519.Signing.PrivateKey())
        let server = try await LoopbackSSHServer.start(
            hostKey: serverKey,
            username: "deploy",
            password: "secret-pass",
            authorizedPublicKeyFingerprint: nil,
            virtualFS: vfs
        )
        try await runWindowIsolationChecks(paths: dirs.withPort(server.port))
        await server.stop()
    }

    @MainActor
    private func runWindowIsolationChecks(paths: LoopbackTestPaths) async throws {
        let credStore = EphemeralWindowCredStore()
        let passRef = SecretReference(kind: .password)
        try await credStore.saveSecret(Data("secret-pass".utf8), for: passRef, requireTouchID: false)
        let connStore = ConnectionStore(fileURL: paths.root.appendingPathComponent("connections.json"))
        let trustStore = HostTrustStore(backingStore: EphemeralTrustBacking())
        let snippetStore = CommandSnippetStore(fileURL: paths.root.appendingPathComponent("snippets.json"))

        let profile = ConnectionProfile(
            name: "Prod Loopback",
            protocolType: .sftp,
            host: "127.0.0.1",
            port: paths.port,
            username: "deploy",
            passwordRef: passRef,
            defaultRemotePath: "/"
        )
        try await connStore.saveProfile(profile)

        let windowA = AppState(
            credentialStore: credStore,
            hostTrustStore: trustStore,
            connectionStore: connStore,
            transferJournal: nil,
            snippetStore: snippetStore
        )
        let windowB = AppState(
            credentialStore: credStore,
            hostTrustStore: trustStore,
            connectionStore: connStore,
            transferJournal: nil,
            snippetStore: snippetStore
        )
        await windowA.refreshProfilesAndGroups()
        await windowB.refreshProfilesAndGroups()

        let trustTask = trustFirstChallenge(on: windowA)
        await windowA.refreshLocalDirectory(paths.localDirA)
        await windowA.connect(profile: profile, openInNewTab: false)
        _ = await trustTask.value

        #expect(windowA.activeSessions.count == 1)
        #expect(windowA.workspaceTabs.first?.title == "Prod Loopback")
        #expect(windowB.activeSessions.isEmpty)
        #expect(windowB.currentSession == nil)
        #expect(windowB.workspaceTabs.first?.sessionID == nil)

        await assertPairedMultiTabBehavior(windowA: windowA, profile: profile, paths: paths)
        windowA.prepareFastShutdown()
        windowB.prepareFastShutdown()
        await windowA.shutdownAsyncResources()
        await windowB.shutdownAsyncResources()
    }

    @MainActor
    private func assertPairedMultiTabBehavior(
        windowA: AppState,
        profile: ConnectionProfile,
        paths: LoopbackTestPaths
    ) async {
        await windowA.connect(profile: profile, openInNewTab: true)
        #expect(windowA.activeSessions.count == 2)
        #expect(windowA.workspaceTabs.count == 2)
        #expect(windowA.workspaceTabs[1].title == "Prod Loopback (#2)")

        await windowA.refreshLocalDirectory(paths.localDirB)
        let firstTabID = windowA.workspaceTabs[0].id
        let secondTabID = windowA.workspaceTabs[1].id
        await windowA.selectWorkspaceTab(id: firstTabID)
        #expect(windowA.localCurrentURL.standardizedFileURL == paths.localDirA.standardizedFileURL)
        await windowA.selectWorkspaceTab(id: secondTabID)
        #expect(windowA.localCurrentURL.standardizedFileURL == paths.localDirB.standardizedFileURL)

        await windowA.closeWorkspaceTab(id: secondTabID)
        #expect(windowA.workspaceTabs.count == 1)
        #expect(windowA.activeSessions.count == 1)

        await windowA.disconnectAllSessions(forProfileID: profile.id)
        #expect(windowA.activeSessions.isEmpty)
        #expect(windowA.workspaceTabs.count == 1)
        #expect(windowA.workspaceTabs[0].sessionID == nil)
    }

    @Test("WinSCP custom commands: CWE-78 quoting, gzip upload, SHA-256 verification and file comparison")
    func winSCPCommandsAndQuoting() async throws {
        let quoted = try PathValidator.escapePOSIXSingleQuoted("file'name; rm -rf /")
        #expect(quoted == "'file'\\''name; rm -rf /'")
        #expect(throws: AppError.self) {
            _ = try PathValidator.escapePOSIXSingleQuoted("bad\0name")
        }

        let dirs = try LoopbackTestPaths.createDirectories(prefix: "SparkleWinSCP")
        defer { try? FileManager.default.removeItem(at: dirs.root) }
        let payload = Data("SparkleSFTP WinSCP test payload\n".utf8)
        let localFileURL = dirs.localDirA.appendingPathComponent("sample.txt")
        try payload.write(to: localFileURL)
        try payload.write(to: dirs.remoteRoot.appendingPathComponent("sample.txt"))

        let vfs = try LoopbackSFTPVirtualFS(rootURL: dirs.remoteRoot)
        let serverKey = NIOSSHPrivateKey(ed25519Key: Curve25519.Signing.PrivateKey())
        let server = try await LoopbackSSHServer.start(
            hostKey: serverKey,
            username: "tester",
            password: "pw",
            authorizedPublicKeyFingerprint: nil,
            virtualFS: vfs
        )
        try await runWinSCPCommandChecks(
            paths: dirs.withPort(server.port),
            payload: payload,
            localFileURL: localFileURL
        )
        await server.stop()
    }

    @MainActor
    private func runWinSCPCommandChecks(
        paths: LoopbackTestPaths,
        payload: Data,
        localFileURL: URL
    ) async throws {
        let appState = AppState(
            credentialStore: EphemeralWindowCredStore(),
            hostTrustStore: HostTrustStore(backingStore: EphemeralTrustBacking()),
            connectionStore: ConnectionStore(fileURL: paths.root.appendingPathComponent("conn.json")),
            transferJournal: nil,
            snippetStore: CommandSnippetStore(fileURL: paths.root.appendingPathComponent("snippets.json"))
        )
        appState.quickConnectProtocol = .sftp
        appState.quickConnectHost = "127.0.0.1"
        appState.quickConnectPort = String(paths.port)
        appState.quickConnectUsername = "tester"
        appState.quickConnectPassword = "pw"
        appState.quickConnectSaveProfile = false

        let trustTask = trustFirstChallenge(on: appState)
        await appState.refreshLocalDirectory(paths.localDirA)
        await appState.performQuickConnect()
        _ = await trustTask.value

        #expect(appState.activeSessions.count == 1)
        let localItem = try #require(appState.localFiles.allFiles.first { $0.name == "sample.txt" })

        await appState.compressAndUploadLocalFiles([localItem])
        let uploadedGzData = try Data(contentsOf: paths.remoteRoot.appendingPathComponent("sample.txt.gz"))
        let roundTrip = try ZlibCompressionCodec.decompress(uploadedGzData)
        #expect(roundTrip == payload)

        await appState.verifySHA256Checksum(for: localItem, isLocal: true)
        let expectedHex = try await SHA256Verifier.computeHexDigest(of: localFileURL)
        #expect(appState.pendingChecksumReport?.sha256 == expectedHex)

        await appState.compareWithOppositePane(file: localItem, isLocal: true)
        #expect(appState.pendingComparisonReport?.verdictKey == "compare.identical")
        #expect(appState.pendingComparisonReport?.localSHA256 == expectedHex)
        #expect(appState.pendingComparisonReport?.remoteSHA256 == expectedHex)

        appState.selectAllLocalFiles()
        #expect(appState.selectedLocalFileIDs.contains(localItem.id))
        await appState.insertFileNamesToCommandLine(files: [localItem], useFullPath: false)
        #expect(appState.isTerminalVisible)
        #expect(!appState.terminalManager.sessions.isEmpty)

        appState.prepareFastShutdown()
        await appState.shutdownAsyncResources()
    }

    @MainActor
    private func trustFirstChallenge(on state: AppState) -> Task<Void, Never> {
        Task {
            for _ in 0 ..< 40 {
                if state.pendingHostChallenge != nil {
                    state.resolveHostChallenge(trusted: true)
                    break
                }
                try? await Task.sleep(for: .milliseconds(25))
            }
        }
    }
}
