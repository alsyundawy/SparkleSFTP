import Crypto
import Foundation
import NIOSSH
import SparkleCore
@testable import SparkleDesignSystem
@testable import SparkleFeatures
@testable import SparkleNetworking
@testable import SparklePersistence
@testable import SparkleSecurity
@testable import SparkleTerminal
@testable import SparkleTransferEngine
import Testing

@Suite("Toolchain Integration, Multi-Thread SFTP & FileZilla Conflict Tests")
struct ToolchainAndConflictTests {
    @Test("Zlib codec round-trips zlib/gzip payloads and rejects zip-bomb overflows")
    func zlibCodecAndOverflowProtection() throws {
        let sample = Data(repeating: 0x41, count: 64 * 1024) + Data("SparkleSFTP-zlib-payload".utf8)
        for format in [CompressionFormat.zlib, .gzip] {
            let compressed = try ZlibCompressionCodec.compress(sample, level: 6, format: format)
            #expect(compressed.count < sample.count)
            let restored = try ZlibCompressionCodec.decompress(compressed, maxOutputBytes: 128 * 1024)
            #expect(restored == sample)
            #expect(throws: AppError.self) {
                _ = try ZlibCompressionCodec.decompress(compressed, maxOutputBytes: 1024)
            }
        }
    }

    @Test("ToolchainInspector reports linked libcurl, zlib, libssh2 probe, shells & host stack")
    func toolchainInspectionSnapshot() async {
        let curlVer = ToolchainInspector.curlVersionSummary()
        #expect(curlVer.lowercased().contains("libcurl") || curlVer.lowercased().contains("curl"))
        #expect(!ZlibCompressionCodec.libraryVersion.isEmpty)
        _ = ToolchainInspector.probeLibssh2()
        #expect(!ToolchainInspector.detectAvailableShells().isEmpty)

        let report = await ToolchainInspector.inspectHostToolchain(runSubprocesses: false)
        let ids = Set(report.libraries.map(\.id))
        #expect(ids == ["niossh", "libcurl", "zlib", "libssh2", "openssl", "openssh", "shell", "iterm"])
        #expect(report.libraries.first { $0.id == "zlib" }?.isAvailable == true)
    }

    @Test("ExternalTerminalLauncher validates targets and builds sanitized SSH commands")
    func externalTerminalCommandAndSanitization() throws {
        let profile = ConnectionProfile(
            name: "App Server", protocolType: .sftp, host: "app.example.com", port: 2222, username: "deploy"
        )
        let jump = ConnectionProfile(
            name: "Bastion", protocolType: .sftp, host: "bastion.example.com", port: 2200, username: "jump"
        )
        let sshURL = try ExternalTerminalLauncher.buildSSHURL(for: profile)
        #expect(sshURL.absoluteString == "ssh://deploy@app.example.com:2222")

        let args = try ExternalTerminalLauncher.buildOpenSSHCommandParts(
            for: profile, jumpProfile: jump, sshBinaryPath: "/usr/bin/ssh"
        )
        #expect(args == [
            "/usr/bin/ssh", "-p", "2222", "-o", "ServerAliveInterval=30",
            "-J", "jump@bastion.example.com:2200", "deploy@app.example.com"
        ])
        #expect(try ExternalTerminalLauncher.escapePOSIXSingleQuoted("a'b") == "'a'\\''b'")
        #expect(throws: AppError.self) {
            _ = try ExternalTerminalLauncher.validateNoControlCharacters("bad\nhost")
        }
    }

    @Test("FileZilla conflict policies evaluate size/time/resume rules and scoped queue overrides")
    func fileZillaConflictPoliciesAndScopes() async {
        let now = Date()
        let older = now.addingTimeInterval(-60)
        let newerCtx = ConflictContext(
            taskID: UUID(), direction: .upload, sourceDisplayPath: "/src/app.bin",
            destinationDisplayPath: "/dst/app.bin", existingSize: 500, incomingSize: 900,
            existingModifiedAt: older, incomingModifiedAt: now
        )
        #expect(ConflictResolver.evaluateNonInteractivePolicy(
            .overwriteIfNewer, context: newerCtx, originalFilename: "app.bin"
        ) == .overwrite)
        #expect(ConflictResolver.evaluateNonInteractivePolicy(
            .overwriteIfDifferentSize, context: newerCtx, originalFilename: "app.bin"
        ) == .overwrite)
        #expect(ConflictResolver.evaluateNonInteractivePolicy(
            .resume, context: newerCtx, originalFilename: "app.bin"
        ) == .resume)

        let identicalCtx = ConflictContext(
            taskID: UUID(), direction: .download, sourceDisplayPath: "/src/same.bin",
            destinationDisplayPath: "/dst/same.bin", existingSize: 500, incomingSize: 500,
            existingModifiedAt: now, incomingModifiedAt: older
        )
        #expect(ConflictResolver.evaluateNonInteractivePolicy(
            .overwriteIfDifferentSizeOrNewer, context: identicalCtx, originalFilename: "same.bin"
        ) == .skip)

        let resolver = ConflictResolver(defaultPolicy: .ask) { _ in .skip }
        await resolver.applyQueueRule(.overwrite, scope: .uploadsOnly)
        #expect(await resolver.resolve(newerCtx, originalFilename: "app.bin") == .overwrite)
        #expect(await resolver.resolve(identicalCtx, originalFilename: "same.bin") == .skip)
    }

    @Test("AppState conflict queue serializes concurrent prompts and auto-drains sticky direction rules")
    @MainActor
    func serializedConflictQueueAndStickyDrain() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SparkleConflictQ-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let appState = AppState(
            credentialStore: TestMemoryCredentialStore(),
            connectionStore: ConnectionStore(fileURL: dir.appendingPathComponent("conn.json")),
            transferJournal: nil,
            snippetStore: CommandSnippetStore(fileURL: dir.appendingPathComponent("snippets.json"))
        )
        let now = Date()
        let up1 = ConflictContext(
            taskID: UUID(), direction: .upload, sourceDisplayPath: "/a1", destinationDisplayPath: "/r/a1",
            existingSize: 100, incomingSize: 200, existingModifiedAt: now.addingTimeInterval(-30),
            incomingModifiedAt: now
        )
        let up2 = ConflictContext(
            taskID: UUID(), direction: .upload, sourceDisplayPath: "/a2", destinationDisplayPath: "/r/a2",
            existingSize: 100, incomingSize: 200, existingModifiedAt: now.addingTimeInterval(-30),
            incomingModifiedAt: now
        )
        let down = ConflictContext(
            taskID: UUID(), direction: .download, sourceDisplayPath: "/r/b", destinationDisplayPath: "/b",
            existingSize: 200, incomingSize: 200
        )

        let task1 = Task { @MainActor in await appState.promptConflictResolution(up1) }
        let task2 = Task { @MainActor in await appState.promptConflictResolution(up2) }
        let task3 = Task { @MainActor in await appState.promptConflictResolution(down) }
        while appState.pendingConflictQueue.count < 3 {
            await Task.yield()
        }

        #expect(appState.pendingConflict?.id == up1.id)
        #expect(appState.pendingConflictQueue.count == 3)

        appState.handleConflictResolution(
            .overwrite,
            applyToQueue: true,
            queuePolicy: .overwriteIfNewer,
            scope: .uploadsOnly
        )
        #expect(await task1.value == .overwrite)
        #expect(await task2.value == .overwrite)
        #expect(appState.pendingConflict?.id == down.id)
        #expect(appState.hasActiveConflictQueueRules)

        appState.handleConflictResolution(
            .rename(newFilename: "b-copy"),
            applyToQueue: false,
            queuePolicy: nil,
            scope: .all
        )
        #expect(await task3.value == .rename(newFilename: "b-copy"))
        #expect(appState.pendingConflict == nil)
    }

    @Test("Pipelined SFTP multi-chunk upload and download preserves SHA-256 across 512KB payload")
    func pipelinedMultiChunkSFTPTransfer() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SparklePipe-\(UUID())")
        let remoteRoot = root.appendingPathComponent("remote", isDirectory: true)
        let localDir = root.appendingPathComponent("local", isDirectory: true)
        try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let virtualFS = try LoopbackSFTPVirtualFS(rootURL: remoteRoot)
        let server = try await LoopbackSSHServer.start(
            hostKey: NIOSSHPrivateKey(ed25519Key: Curve25519.Signing.PrivateKey()),
            username: "pipe",
            password: "pipe-password",
            authorizedPublicKeyFingerprint: nil,
            virtualFS: virtualFS
        )
        let credStore = TestMemoryCredentialStore()
        let passRef = SecretReference(kind: .password)
        try await credStore.saveSecret(Data("pipe-password".utf8), for: passRef, requireTouchID: false)

        let profile = ConnectionProfile(
            name: "Pipeline", protocolType: .sftp, host: "127.0.0.1",
            port: server.port, username: "pipe", authMethod: .password, passwordRef: passRef
        )
        let sshClient = SSHClientService(
            profile: profile,
            credentialStore: credStore,
            hostTrustStore: HostTrustStore(backingStore: TestMemoryHostTrustBacking())
        ) { _ in true }
        let sftp = SFTPService(profile: profile, sshClient: sshClient, pipelineDepth: 8)
        try await sftp.connect()

        var rawBytes = [UInt8](repeating: 0, count: 512 * 1024 + 37)
        for index in rawBytes.indices {
            rawBytes[index] = UInt8((index &* 31 &+ 7) & 0xFF)
        }
        let payload = Data(rawBytes)
        let expectedDigest = SHA256.hash(data: payload)

        let sourceURL = localDir.appendingPathComponent("source.bin")
        let downloadedURL = localDir.appendingPathComponent("downloaded.bin")
        try payload.write(to: sourceURL)

        let remotePath = RemotePath(rawValue: "/pipelined.bin")
        try await sftp.upload(from: sourceURL, to: remotePath, offset: 0) { _ in }
        try await sftp.download(from: remotePath, to: downloadedURL, offset: 0) { _ in }

        let restored = try Data(contentsOf: downloadedURL)
        #expect(restored.count == payload.count)
        #expect(SHA256.hash(data: restored) == expectedDigest)

        try await sftp.disconnect(policy: .cancelAllTransfers)
        await server.stop()
    }

    @Test("EN and ID locales include synchronized 309-key coverage for new conflict and toolchain UI")
    func localeParityForNewFeatures() {
        let english = LocalizationCatalog.loadBundledStrings(code: "en")
        let indonesian = LocalizationCatalog.loadBundledStrings(code: "id")
        #expect(english.count >= 309)
        #expect(english.count == indonesian.count)

        let requiredKeys = [
            "prefs.conflictOverwriteIfNewer",
            "prefs.conflictOverwriteIfDiffSize",
            "prefs.conflictOverwriteIfDiffOrNewer",
            "transfers.fileAlreadyExists",
            "prefs.languageLayoutHint",
            "nav.localShell",
            "nav.openInITerm"
        ]
        for key in requiredKeys {
            #expect(english[key]?.isEmpty == false)
            #expect(indonesian[key]?.isEmpty == false)
        }
    }
}
