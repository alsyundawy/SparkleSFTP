import Crypto
import Foundation
import NIOCore
import NIOPosix
import NIOSSH
import SparkleCore
import SparkleNetworking
import SparkleSecurity
import SparkleTerminal
import SparkleTransferEngine
import Testing

private actor TestMemoryCredentialStore: CredentialStoreProtocol {
    private var storage: [String: Data] = [:]

    func saveSecret(_ data: Data, for reference: SecretReference, requireTouchID: Bool) async throws {
        storage[reference.accountKey] = data
    }

    func loadSecret(for reference: SecretReference, prompt: String?) async throws -> Data {
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

private actor TestMemoryHostTrustBacking: HostTrustBackingStore {
    private var blob: Data?
    func loadTrustBlob() async throws -> Data? { blob }
    func saveTrustBlob(_ data: Data) async throws { blob = data }
}

private actor PromptCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}

@Suite("SparkleSFTP Live Encrypted Loopback SSH/SFTP Tests")
struct LoopbackSFTPIntegrationTests {
    @Test("Live loopback SSH/SFTP transfer, TOFU trust reuse, and rotated host-key blocking")
    func loopbackPasswordSFTPAndHostRotation() async throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("SparkleLoopback-\(UUID())")
        let serverDir = tempRoot.appendingPathComponent("remote", isDirectory: true)
        let localDir = tempRoot.appendingPathComponent("local", isDirectory: true)
        try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let virtualFS = try LoopbackSFTPVirtualFS(rootURL: serverDir)
        let serverHostKey = NIOSSHPrivateKey(ed25519Key: Curve25519.Signing.PrivateKey())
        let server = try await LoopbackSSHServer.start(
            hostKey: serverHostKey,
            username: "deploy",
            password: "correct-horse-battery",
            authorizedPublicKeyFingerprint: nil,
            virtualFS: virtualFS
        )

        let credStore = TestMemoryCredentialStore()
        let passRef = SecretReference(kind: .password)
        try await credStore.saveSecret(Data("correct-horse-battery".utf8), for: passRef, requireTouchID: false)
        let trustStore = HostTrustStore(backingStore: TestMemoryHostTrustBacking())
        let promptCounter = PromptCounter()

        let profile = ConnectionProfile(
            name: "Loopback SFTP",
            protocolType: .sftp,
            host: "127.0.0.1",
            port: server.port,
            username: "deploy",
            authMethod: .password,
            passwordRef: passRef
        )

        let sshClient = SSHClientService(
            profile: profile,
            credentialStore: credStore,
            hostTrustStore: trustStore
        ) { _ in
            await promptCounter.increment()
            return true
        }
        let sftp = SFTPService(profile: profile, sshClient: sshClient)
        try await sftp.connect()
        #expect(await promptCounter.count == 1)

        try await runRealSFTPOperations(sftp: sftp, profileID: profile.id, localDir: localDir, serverDir: serverDir)
        try await sftp.disconnect(policy: .cancelAllTransfers)
        await server.stop()

        try await verifyHostKeyRotationBlocked(
            originalHostKey: serverHostKey,
            passwordRef: passRef,
            credStore: credStore,
            trustStore: trustStore,
            virtualFS: virtualFS
        )
    }

    private func verifyHostKeyRotationBlocked(
        originalHostKey: NIOSSHPrivateKey,
        passwordRef: SecretReference,
        credStore: TestMemoryCredentialStore,
        trustStore: HostTrustStore,
        virtualFS: LoopbackSFTPVirtualFS
    ) async throws {
        let rotatedKey = NIOSSHPrivateKey(ed25519Key: Curve25519.Signing.PrivateKey())
        let mitmServer = try await LoopbackSSHServer.start(
            hostKey: rotatedKey,
            username: "deploy",
            password: "correct-horse-battery",
            authorizedPublicKeyFingerprint: nil,
            virtualFS: virtualFS
        )
        let rotatedProfile = ConnectionProfile(
            name: "Loopback MitM",
            protocolType: .sftp,
            host: "127.0.0.1",
            port: mitmServer.port,
            username: "deploy",
            authMethod: .password,
            passwordRef: passwordRef
        )
        let expectedFP = SSHKeyFingerprint.sha256(for: originalHostKey.publicKey)
        try await trustStore.trust(host: "127.0.0.1", port: mitmServer.port, fingerprint: expectedFP)
        let badClient = SSHClientService(
            profile: rotatedProfile,
            credentialStore: credStore,
            hostTrustStore: trustStore
        )
        await #expect(throws: AppError.hostKeyMismatch(
            host: "127.0.0.1",
            expected: expectedFP,
            got: SSHKeyFingerprint.sha256(for: rotatedKey.publicKey)
        )) {
            try await badClient.connect()
        }
        await mitmServer.stop()
    }

    @Test("Live loopback SSH Ed25519 public-key auth & DirectTCPIP port forwarding tunnel")
    func loopbackPublicKeyAndPortForwarding() async throws {
        let serverDir = FileManager.default.temporaryDirectory.appendingPathComponent("SparkleTunnel-\(UUID())")
        defer { try? FileManager.default.removeItem(at: serverDir) }
        let virtualFS = try LoopbackSFTPVirtualFS(rootURL: serverDir)

        let signingKey = Curve25519.Signing.PrivateKey()
        let userSSHKey = NIOSSHPrivateKey(ed25519Key: signingKey)
        let keyFingerprint = SSHKeyFingerprint.sha256(for: userSSHKey.publicKey)
        let pem = TestPEMBuilder.encodeOpenSSHEd25519(signingKey: signingKey)

        let serverHostKey = NIOSSHPrivateKey(ed25519Key: Curve25519.Signing.PrivateKey())
        let server = try await LoopbackSSHServer.start(
            hostKey: serverHostKey,
            username: "ops",
            password: nil,
            authorizedPublicKeyFingerprint: keyFingerprint,
            virtualFS: virtualFS
        )

        let credStore = TestMemoryCredentialStore()
        let keyRef = SecretReference(kind: .privateKey)
        try await credStore.saveSecret(Data(pem.utf8), for: keyRef, requireTouchID: false)
        let trustStore = HostTrustStore(backingStore: TestMemoryHostTrustBacking())
        let profile = ConnectionProfile(
            name: "Loopback Key",
            protocolType: .sftp,
            host: "127.0.0.1",
            port: server.port,
            username: "ops",
            authMethod: .publicKey,
            privateKeyRef: keyRef
        )
        let client = SSHClientService(
            profile: profile,
            credentialStore: credStore,
            hostTrustStore: trustStore
        ) { _ in true }
        try await client.connect()

        let forwarder = PortForwardingManager()
        let rule = PortForwardingRule(
            name: "Echo",
            direction: .local,
            bindHost: "127.0.0.1",
            bindPort: 0,
            targetHost: "127.0.0.1",
            targetPort: 9999
        )
        let tunnel = try await forwarder.startLocalForward(rule: rule, sshClient: client)
        let echoed = try await echoThroughTCP(port: tunnel.listeningPort, message: "sparkle-tunnel-ping")
        #expect(echoed == "sparkle-tunnel-ping")

        await forwarder.stopAll()
        try await client.disconnect(policy: .cancelAllTransfers)
        await server.stop()
    }

    private func runRealSFTPOperations(
        sftp: SFTPService,
        profileID: UUID,
        localDir: URL,
        serverDir: URL
    ) async throws {
        let payload = Data("SparkleSFTP Live Encrypted Payload".utf8)
        let digest = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        let srcFile = localDir.appendingPathComponent("upload.txt")
        try payload.write(to: srcFile)

        try await sftp.createDirectory(at: "/releases")
        let queue = TransferQueue { _ in sftp }
        let uploadMeta = TransferTaskMetadata(
            direction: .upload,
            source: .local(url: srcFile),
            destination: .remote(profileID: profileID, host: "127.0.0.1", path: "/releases/upload.txt"),
            totalBytes: Int64(payload.count)
        )
        _ = await queue.enqueue(uploadMeta)
        try await Task.sleep(for: .milliseconds(300))

        #expect(try Data(contentsOf: serverDir.appendingPathComponent("releases/upload.txt")) == payload)
        let listed = try await sftp.listDirectory(at: "/releases")
        #expect(listed.map(\.name).contains("upload.txt"))

        let downloadFile = localDir.appendingPathComponent("downloaded.txt")
        let downMeta = TransferTaskMetadata(
            direction: .download,
            source: .remote(profileID: profileID, host: "127.0.0.1", path: "/releases/upload.txt"),
            destination: .local(url: downloadFile),
            totalBytes: Int64(payload.count),
            expectedSHA256: digest
        )
        _ = await queue.enqueue(downMeta)
        try await Task.sleep(for: .milliseconds(300))
        #expect(try Data(contentsOf: downloadFile) == payload)

        try await sftp.rename(from: "/releases/upload.txt", to: "/releases/final.txt")
        try await sftp.setPermissions(0o600, at: "/releases/final.txt")
        try await sftp.delete(at: "/releases/final.txt", isDirectory: false)
    }

    private func echoThroughTCP(port: Int, message: String) async throws -> String {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        do {
            let collector = EchoCollectorHandler()
            let channel = try await ClientBootstrap(group: group)
                .channelInitializer { clientChannel in
                    clientChannel.pipeline.addHandler(collector)
                }
                .connect(host: "127.0.0.1", port: port)
                .get()

            var out = channel.allocator.buffer(capacity: message.utf8.count)
            out.writeString(message)
            try await channel.writeAndFlush(out)
            let received = try await collector.waitForEcho(expectedCount: message.utf8.count)
            try? await channel.close().get()
            try? await group.shutdownGracefully()
            return received
        } catch {
            try? await group.shutdownGracefully()
            throw error
        }
    }
}

private final class EchoCollectorHandler:
    ChannelInboundHandler,
    @unchecked Sendable { // JUSTIFICATION: Single test EventLoop channel collects bytes for async promise.
    typealias InboundIn = ByteBuffer
    private let lock = NSLock()
    private var accumulated = Data()
    private var expectedCount = 0
    private var continuation: CheckedContinuation<String, Error>?

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer = unwrapInboundIn(data)
        let bytes = buffer.readBytes(length: buffer.readableBytes) ?? []
        lock.lock()
        accumulated.append(contentsOf: bytes)
        let ready = expectedCount > 0 && accumulated.count >= expectedCount
        let cont = ready ? continuation : nil
        let result = ready ? (String(data: accumulated.prefix(expectedCount), encoding: .utf8) ?? "") : ""
        if ready { continuation = nil }
        lock.unlock()
        cont?.resume(returning: result)
    }

    func waitForEcho(expectedCount: Int) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            lock.lock()
            self.expectedCount = expectedCount
            if accumulated.count >= expectedCount {
                let text = String(data: accumulated.prefix(expectedCount), encoding: .utf8) ?? ""
                lock.unlock()
                cont.resume(returning: text)
                return
            }
            self.continuation = cont
            lock.unlock()
        }
    }
}

private enum TestPEMBuilder {
    static func encodeOpenSSHEd25519(signingKey: Curve25519.Signing.PrivateKey) -> String {
        func sshString(_ data: Data) -> Data {
            var len = UInt32(data.count).bigEndian
            return Data(bytes: &len, count: 4) + data
        }
        func sshString(_ text: String) -> Data { sshString(Data(text.utf8)) }

        let pub = signingKey.publicKey.rawRepresentation
        let pubBlob = sshString("ssh-ed25519") + sshString(pub)
        var priv = Data([0x10, 0x20, 0x30, 0x40, 0x10, 0x20, 0x30, 0x40])
        priv += sshString("ssh-ed25519")
        priv += sshString(pub)
        priv += sshString(signingKey.rawRepresentation + pub)
        priv += sshString("loopback")
        while priv.count % 8 != 0 { priv.append(1) }

        var container = Data("openssh-key-v1\0".utf8) + sshString("none") + sshString("none") + sshString(Data())
        var count = UInt32(1).bigEndian
        container += Data(bytes: &count, count: 4) + sshString(pubBlob) + sshString(priv)
        let b64 = container.base64EncodedString()
        return "-----BEGIN OPENSSH PRIVATE KEY-----\n\(b64)\n-----END OPENSSH PRIVATE KEY-----"
    }
}
