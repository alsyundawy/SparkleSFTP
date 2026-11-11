import Crypto
import Foundation
import NIOSSH
import SparkleCore
@testable import SparkleNetworking
@testable import SparkleSecurity
@testable import SparkleTransferEngine
import Testing

@Suite("Loopback Pipelined SFTP Pause & Resume Tests")
struct LoopbackTransferResumeTests {
    @Test("Real loopback SFTP 512 KB upload & download pause and immediate retry complete byte-accurately")
    func pipelinedLoopbackPauseAndRetry() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SparkleLoopResume-\(UUID())")
        let remoteRoot = dir.appendingPathComponent("remote")
        let localDir = dir.appendingPathComponent("local")
        try FileManager.default.createDirectory(at: remoteRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let size = 512 * 1024
        let raw = makeDeterministicPayload(size: size)
        let uploadSrc = localDir.appendingPathComponent("upload.bin")
        let downloadDst = localDir.appendingPathComponent("download.bin")
        try raw.write(to: uploadSrc)
        try raw.write(to: remoteRoot.appendingPathComponent("download.bin"))

        let ctx = try await startConnectedQueue(remoteRoot: remoteRoot)
        let queue = ctx.queue
        let upID = await queue.enqueue(
            TransferTaskMetadata(
                direction: .upload,
                source: .local(url: uploadSrc),
                destination: .remote(profileID: ctx.profileID, host: "loop", path: "/uploaded.bin"),
                totalBytes: Int64(size)
            )
        )
        try? await Task.sleep(for: .milliseconds(25))
        await queue.pause(id: upID)
        await queue.retry(id: upID)

        let downID = await queue.enqueue(
            TransferTaskMetadata(
                direction: .download,
                source: .remote(profileID: ctx.profileID, host: "loop", path: "/download.bin"),
                destination: .local(url: downloadDst),
                totalBytes: Int64(size)
            )
        )
        try? await Task.sleep(for: .milliseconds(25))
        await queue.pause(id: downID)
        await queue.retry(id: downID)

        let finalUp = await waitUntilDone(in: queue, id: upID)
        let finalDown = await waitUntilDone(in: queue, id: downID)
        #expect(finalUp?.status == .completed)
        #expect(finalDown?.status == .completed)
        #expect(try Data(contentsOf: remoteRoot.appendingPathComponent("uploaded.bin")) == raw)
        #expect(try Data(contentsOf: downloadDst) == raw)

        try? await ctx.sftp.disconnect(policy: .cancelAllTransfers)
        await ctx.server.stop()
    }

    private struct LoopbackQueueContext {
        let profileID: UUID
        let server: LoopbackSSHServer
        let sftp: SFTPService
        let queue: TransferQueue
    }

    private func makeDeterministicPayload(size: Int) -> Data {
        Data((0 ..< size).map { UInt8(($0 &* 31 &+ 7) & 0xFF) })
    }

    private func startConnectedQueue(remoteRoot: URL) async throws -> LoopbackQueueContext {
        let vfs = try LoopbackSFTPVirtualFS(rootURL: remoteRoot)
        let server = try await LoopbackSSHServer.start(
            hostKey: NIOSSHPrivateKey(ed25519Key: Curve25519.Signing.PrivateKey()),
            username: "ops",
            password: "pw",
            authorizedPublicKeyFingerprint: nil,
            virtualFS: vfs
        )
        let credStore = LoopbackCredStore()
        let passRef = SecretReference(kind: .password)
        try await credStore.saveSecret(Data("pw".utf8), for: passRef, requireTouchID: false)
        let trustStore = HostTrustStore(backingStore: LoopbackTrustBacking())
        let profile = ConnectionProfile(
            name: "Loopback Resume",
            protocolType: .sftp,
            host: "127.0.0.1",
            port: server.port,
            username: "ops",
            authMethod: .password,
            passwordRef: passRef
        )
        let sshClient = SSHClientService(
            profile: profile,
            credentialStore: credStore,
            hostTrustStore: trustStore
        ) { _ in
            true
        }
        let sftp = SFTPService(profile: profile, sshClient: sshClient)
        try await sftp.connect()
        let queue = TransferQueue(
            conflictResolver: ConflictResolver(defaultPolicy: .overwrite)
        ) { _ in sftp }
        return LoopbackQueueContext(profileID: profile.id, server: server, sftp: sftp, queue: queue)
    }

    private func waitUntilDone(in queue: TransferQueue, id: UUID) async -> TransferSnapshot? {
        let deadline = ContinuousClock.now + .seconds(15)
        while ContinuousClock.now < deadline {
            let snaps = await queue.currentSnapshots()
            if let snap = snaps.first(where: { $0.id == id }), snap.status.isTerminal {
                return snap
            }
            try? await Task.sleep(for: .milliseconds(30))
        }
        return await queue.currentSnapshots().first(where: { $0.id == id })
    }
}

private actor LoopbackCredStore: CredentialStoreProtocol {
    private var storage: [String: Data] = [:]

    func saveSecret(_ data: Data, for ref: SecretReference, requireTouchID _: Bool) async throws {
        storage[ref.accountKey] = data
    }

    func loadSecret(for ref: SecretReference, prompt _: String?) async throws -> Data {
        guard let data = storage[ref.accountKey] else {
            throw AppError.credentialNotFound(service: ref.accountKey)
        }
        return data
    }

    func deleteSecret(for ref: SecretReference) async throws {
        storage.removeValue(forKey: ref.accountKey)
    }

    func hasSecret(for ref: SecretReference) async -> Bool {
        storage[ref.accountKey] != nil
    }
}

private actor LoopbackTrustBacking: HostTrustBackingStore {
    private var blob: Data?

    func loadTrustBlob() async throws -> Data? {
        blob
    }

    func saveTrustBlob(_ data: Data) async throws {
        blob = data
    }
}
