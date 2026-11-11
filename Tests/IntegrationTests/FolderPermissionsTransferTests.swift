import Crypto
import Foundation
import NIOSSH
import SparkleCore
@testable import SparkleFeatures
@testable import SparklePersistence
@testable import SparkleSecurity
@testable import SparkleTerminal
import Testing

private actor FolderTransferCredStore: CredentialStoreProtocol {
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

private actor FolderTransferTrustBacking: HostTrustBackingStore {
    private var blob: Data?

    func loadTrustBlob() async throws -> Data? {
        blob
    }

    func saveTrustBlob(_ data: Data) async throws {
        blob = data
    }
}

@Suite("SpeedMeter, Recursive Folder & POSIX Permissions Preservation Tests")
struct FolderPermissionsTransferTests {
    @Test("TransferSpeedMeter calculates positive rate even for fast transfers")
    func speedMeterFastTransferRate() async {
        let meter = TransferSpeedMeter(totalBytes: 262_144, initialOffset: 0, minEmitInterval: .zero)
        try? await Task.sleep(for: .milliseconds(15))
        let progress = meter.record(absoluteBytes: 262_144, force: true)
        #expect(progress?.bytesTransferred == 262_144)
        #expect((progress?.bytesPerSecond ?? 0) > 262_144)
    }

    @Test("Loopback SFTP recursive folder upload/download preserves empty subdirs, dotfiles & POSIX modes")
    func loopbackRecursiveFolderAndPermissionsPreservation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SparkleFolderPerms-\(UUID())")
        let remoteRoot = root.appendingPathComponent("remote", isDirectory: true)
        let localUploadSrc = root.appendingPathComponent("localSrc/deploy-bundle", isDirectory: true)
        let localDownloadDst = root.appendingPathComponent("localDst", isDirectory: true)
        try FileManager.default.createDirectory(at: localUploadSrc, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: localDownloadDst, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let vfs = try LoopbackSFTPVirtualFS(rootURL: remoteRoot)
        let server = try await LoopbackSSHServer.start(
            hostKey: NIOSSHPrivateKey(ed25519Key: Curve25519.Signing.PrivateKey()),
            username: "ops",
            password: "pw",
            authorizedPublicKeyFingerprint: nil,
            virtualFS: vfs
        )
        try await runRecursiveTransferVerification(
            root: root,
            remoteRoot: remoteRoot,
            localUploadSrc: localUploadSrc,
            localDownloadDst: localDownloadDst,
            port: server.port
        )
        await server.stop()
    }

    @MainActor
    private func runRecursiveTransferVerification(
        root: URL,
        remoteRoot: URL,
        localUploadSrc: URL,
        localDownloadDst: URL,
        port: Int
    ) async throws {
        try prepareSampleTree(at: localUploadSrc)
        let state = AppState(
            credentialStore: FolderTransferCredStore(),
            hostTrustStore: HostTrustStore(backingStore: FolderTransferTrustBacking()),
            connectionStore: ConnectionStore(fileURL: root.appendingPathComponent("conn.json")),
            transferJournal: nil,
            snippetStore: CommandSnippetStore(fileURL: root.appendingPathComponent("snip.json"))
        )
        state.didBootstrap = true
        let session = try await connectOpsSession(state: state, port: port)

        await state.enqueueLocalItemUpload(url: localUploadSrc, isDirectory: true, into: session)
        await waitUntilQueueIdle(state: state)
        try assertUploadedTree(remoteRoot: remoteRoot)

        let remoteFolder = RemoteFile(name: "deploy-bundle", path: "/deploy-bundle", size: 0, isDirectory: true)
        await state.enqueueRemoteItemDownload(file: remoteFolder, localParentDir: localDownloadDst, session: session)
        await waitUntilQueueIdle(state: state)
        try assertDownloadedTree(localDownloadDst: localDownloadDst)

        state.prepareFastShutdown()
        await state.shutdownAsyncResources()
    }

    private func prepareSampleTree(at localUploadSrc: URL) throws {
        let emptyDir = localUploadSrc.appendingPathComponent("empty-logs", isDirectory: true)
        let nestedDir = localUploadSrc.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: emptyDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: nestedDir, withIntermediateDirectories: true)

        let scriptURL = nestedDir.appendingPathComponent("run.sh")
        let dotfileURL = localUploadSrc.appendingPathComponent(".htaccess")
        try Data("#!/bin/sh\necho ok\n".utf8).write(to: scriptURL)
        try Data("Deny from all\n".utf8).write(to: dotfileURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dotfileURL.path)
    }

    @MainActor
    private func connectOpsSession(state: AppState, port: Int) async throws -> ActiveSessionModel {
        let credRef = SecretReference(kind: .password)
        try await state.credentialStore.saveSecret(Data("pw".utf8), for: credRef, requireTouchID: false)
        let profile = ConnectionProfile(
            name: "Perms Loopback",
            protocolType: .sftp,
            host: "127.0.0.1",
            port: port,
            username: "ops",
            passwordRef: credRef,
            defaultRemotePath: "/"
        )
        await state.saveProfile(profile, secretString: "pw", passphraseString: nil)

        let trustTask = Task {
            for _ in 0 ..< 40 {
                if state.pendingHostChallenge != nil {
                    state.resolveHostChallenge(trusted: true)
                    break
                }
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
        await state.connect(profile: profile, openInNewTab: false)
        _ = await trustTask.value
        return try #require(state.currentSession)
    }

    private func assertUploadedTree(remoteRoot: URL) throws {
        let uploadedScript = remoteRoot.appendingPathComponent("deploy-bundle/bin/run.sh")
        let uploadedDotfile = remoteRoot.appendingPathComponent("deploy-bundle/.htaccess")
        let uploadedEmpty = remoteRoot.appendingPathComponent("deploy-bundle/empty-logs")
        #expect(FileManager.default.fileExists(atPath: uploadedScript.path))
        #expect(FileManager.default.fileExists(atPath: uploadedDotfile.path))
        #expect(FileManager.default.fileExists(atPath: uploadedEmpty.path))

        let scriptAttrs = try FileManager.default.attributesOfItem(atPath: uploadedScript.path)
        let scriptPerms = ((scriptAttrs[.posixPermissions] as? NSNumber)?.uint32Value ?? 0) & 0o777
        let dotAttrs = try FileManager.default.attributesOfItem(atPath: uploadedDotfile.path)
        let dotPerms = ((dotAttrs[.posixPermissions] as? NSNumber)?.uint32Value ?? 0) & 0o777
        #expect(scriptPerms == 0o755)
        #expect(dotPerms == 0o600)
    }

    private func assertDownloadedTree(localDownloadDst: URL) throws {
        let restoredScript = localDownloadDst.appendingPathComponent("deploy-bundle/bin/run.sh")
        let restoredAttrs = try FileManager.default.attributesOfItem(atPath: restoredScript.path)
        let restoredPerms = ((restoredAttrs[.posixPermissions] as? NSNumber)?.uint32Value ?? 0) & 0o777
        #expect(restoredPerms == 0o755)
        let dotPath = localDownloadDst.appendingPathComponent("deploy-bundle/.htaccess").path
        let emptyPath = localDownloadDst.appendingPathComponent("deploy-bundle/empty-logs").path
        #expect(FileManager.default.fileExists(atPath: dotPath))
        #expect(FileManager.default.fileExists(atPath: emptyPath))
    }

    @Test("TransferSpeedMeter decays stale rate to zero when transfer stalls")
    func speedMeterDecaysWhenStalled() async {
        let meter = TransferSpeedMeter(totalBytes: 1_000_000, initialOffset: 0, minEmitInterval: .zero)
        try? await Task.sleep(for: .milliseconds(25))
        let burst = meter.record(absoluteBytes: 200_000, force: true)
        #expect((burst?.bytesPerSecond ?? 0) > 100_000)

        try? await Task.sleep(for: .milliseconds(2050))
        let stalled = meter.record(absoluteBytes: 200_000, force: true)
        #expect(stalled?.bytesPerSecond == 0)
    }

    @Test("Loopback SFTP recursive folder upload/download restores exact restricted 0o555 folder permissions")
    func loopbackRestrictedDirectoryPermissionsRestored() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SparkleDirMode-\(UUID())")
        let remoteRoot = root.appendingPathComponent("remote", isDirectory: true)
        let localSrc = root.appendingPathComponent("src/locked-dir", isDirectory: true)
        let localDst = root.appendingPathComponent("dst", isDirectory: true)
        let nestedDir = localSrc.appendingPathComponent("inner", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: localDst, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: localSrc.path)
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: nestedDir.path)
            let downloadedLocked = localDst.appendingPathComponent("locked-dir")
            let downloadedInner = downloadedLocked.appendingPathComponent("inner")
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: downloadedLocked.path)
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: downloadedInner.path)
            let remoteLocked = remoteRoot.appendingPathComponent("locked-dir")
            let remoteInner = remoteLocked.appendingPathComponent("inner")
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: remoteLocked.path)
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: remoteInner.path)
            try? FileManager.default.removeItem(at: root)
        }

        try Data("hello\n".utf8).write(to: nestedDir.appendingPathComponent("note.txt"))
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: nestedDir.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: localSrc.path)

        let vfs = try LoopbackSFTPVirtualFS(rootURL: remoteRoot)
        let server = try await LoopbackSSHServer.start(
            hostKey: NIOSSHPrivateKey(ed25519Key: Curve25519.Signing.PrivateKey()),
            username: "ops",
            password: "pw",
            authorizedPublicKeyFingerprint: nil,
            virtualFS: vfs
        )
        try await runRestrictedDirModeCheck(
            root: root,
            remoteRoot: remoteRoot,
            localSrc: localSrc,
            localDst: localDst,
            port: server.port
        )
        await server.stop()
    }

    @MainActor
    private func runRestrictedDirModeCheck(
        root: URL,
        remoteRoot: URL,
        localSrc: URL,
        localDst: URL,
        port: Int
    ) async throws {
        let state = AppState(
            credentialStore: FolderTransferCredStore(),
            hostTrustStore: HostTrustStore(backingStore: FolderTransferTrustBacking()),
            connectionStore: ConnectionStore(fileURL: root.appendingPathComponent("conn.json")),
            transferJournal: nil,
            snippetStore: CommandSnippetStore(fileURL: root.appendingPathComponent("snip.json"))
        )
        state.didBootstrap = true
        let session = try await connectOpsSession(state: state, port: port)

        let localInner = localSrc.appendingPathComponent("inner")
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: localSrc.path)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: localInner.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: localInner.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: localSrc.path)

        await state.enqueueLocalItemUpload(url: localSrc, isDirectory: true, into: session)
        await waitUntilQueueIdle(state: state)
        try? await Task.sleep(for: .milliseconds(350))

        let remoteLocked = remoteRoot.appendingPathComponent("locked-dir")
        let remoteInner = remoteLocked.appendingPathComponent("inner")
        #expect(try posixMode(of: remoteLocked) == 0o555)
        #expect(try posixMode(of: remoteInner) == 0o555)

        let remoteFolder = RemoteFile(
            name: "locked-dir",
            path: "/locked-dir",
            size: 0,
            isDirectory: true,
            permissions: 0o555
        )
        await state.enqueueRemoteItemDownload(file: remoteFolder, localParentDir: localDst, session: session)
        await waitUntilQueueIdle(state: state)
        try? await Task.sleep(for: .milliseconds(350))

        let dLocked = localDst.appendingPathComponent("locked-dir")
        let dInner = dLocked.appendingPathComponent("inner")
        #expect(try posixMode(of: dLocked) == 0o555)
        #expect(try posixMode(of: dInner) == 0o555)

        state.prepareFastShutdown()
        await state.shutdownAsyncResources()
    }

    private func posixMode(of url: URL) throws -> UInt32 {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        return ((attrs[.posixPermissions] as? NSNumber)?.uint32Value ?? 0) & 0o777
    }

    @MainActor
    private func waitUntilQueueIdle(state: AppState) async {
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            let snaps = await state.transferQueue.currentSnapshots()
            if !snaps.isEmpty, snaps.allSatisfy(\.status.isTerminal) {
                return
            }
            try? await Task.sleep(for: .milliseconds(25))
        }
    }
}
