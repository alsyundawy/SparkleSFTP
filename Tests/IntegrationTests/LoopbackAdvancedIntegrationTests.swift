import Crypto
import Foundation
import NIOCore
import NIOSSH
import SparkleCore
import SparkleNetworking
import SparkleSecurity
import SparkleTerminal
import Testing

@Suite("SparkleSFTP Advanced Tunnel, Jump, Proxy & Reverse Forward Tests")
struct LoopbackAdvancedIntegrationTests {
    @Test("Live loopback SSH ProxyJump bastion chain, interactive prompt & remote -R forward")
    func loopbackProxyJumpAndRemoteForward() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SparkleJump-\(UUID())")
        let targetDir = root.appendingPathComponent("target", isDirectory: true)
        try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let bastionFS = try LoopbackSFTPVirtualFS(rootURL: root.appendingPathComponent("bastion", isDirectory: true))
        let targetFS = try LoopbackSFTPVirtualFS(rootURL: targetDir)
        try Data("behind-bastion".utf8).write(to: targetDir.appendingPathComponent("secret.txt"))

        let bastion = try await LoopbackSSHServer.start(
            hostKey: NIOSSHPrivateKey(ed25519Key: Curve25519.Signing.PrivateKey()),
            username: "jumpuser",
            password: "bastion-pass",
            authorizedPublicKeyFingerprint: nil,
            virtualFS: bastionFS
        )
        let target = try await LoopbackSSHServer.start(
            hostKey: NIOSSHPrivateKey(ed25519Key: Curve25519.Signing.PrivateKey()),
            username: "appuser",
            password: "otp-session-token",
            authorizedPublicKeyFingerprint: nil,
            virtualFS: targetFS
        )

        let credStore = TestMemoryCredentialStore()
        let bastionPassRef = SecretReference(kind: .password)
        try await credStore.saveSecret(Data("bastion-pass".utf8), for: bastionPassRef, requireTouchID: false)

        let bastionProfile = ConnectionProfile(
            name: "Bastion",
            protocolType: .sftp,
            host: "127.0.0.1",
            port: bastion.port,
            username: "jumpuser",
            authMethod: .password,
            passwordRef: bastionPassRef
        )
        let targetProfile = ConnectionProfile(
            name: "Target",
            protocolType: .sftp,
            host: "127.0.0.1",
            port: target.port,
            username: "appuser",
            authMethod: .keyboardInteractive,
            jumpHostProfileID: bastionProfile.id
        )

        try await verifyJumpConnection(
            bastionProfile: bastionProfile,
            targetProfile: targetProfile,
            credStore: credStore
        )

        await target.stop()
        await bastion.stop()
    }

    private func verifyJumpConnection(
        bastionProfile: ConnectionProfile,
        targetProfile: ConnectionProfile,
        credStore: TestMemoryCredentialStore
    ) async throws {
        let promptCounter = PromptCounter()
        let client = SSHClientService(
            profile: targetProfile,
            credentialStore: credStore,
            hostTrustStore: HostTrustStore(backingStore: TestMemoryHostTrustBacking()),
            hostTrustPrompt: { _ in true },
            credentialPrompt: { _ in
                await promptCounter.increment()
                return "otp-session-token"
            },
            jumpProfileResolver: { id in id == bastionProfile.id ? bastionProfile : nil }
        )

        let sftp = SFTPService(profile: targetProfile, sshClient: client)
        try await sftp.connect()
        #expect(await promptCounter.count == 1)
        let entries = try await sftp.listDirectory(at: "/")
        #expect(entries.map(\.name).contains("secret.txt"))

        let forwarder = PortForwardingManager()
        let remoteRule = PortForwardingRule(
            name: "Remote Reverse",
            direction: .remote,
            bindHost: "127.0.0.1",
            bindPort: 0,
            targetHost: "127.0.0.1",
            targetPort: 8080
        )
        let remoteTunnel = try await forwarder.startForward(rule: remoteRule, sshClient: client)
        #expect(remoteTunnel.listeningPort > 0)

        await forwarder.stopAll()
        try await sftp.disconnect(policy: .cancelAllTransfers)
    }

    @Test("Live loopback SSH over SOCKS5 and HTTP CONNECT proxy tunnels")
    func loopbackSSHOverSOCKS5AndHTTPProxy() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SparkleProxy-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let virtualFS = try LoopbackSFTPVirtualFS(rootURL: root)
        let server = try await LoopbackSSHServer.start(
            hostKey: NIOSSHPrivateKey(ed25519Key: Curve25519.Signing.PrivateKey()),
            username: "proxied",
            password: "proxy-ssh-secret",
            authorizedPublicKeyFingerprint: nil,
            virtualFS: virtualFS
        )

        let credStore = TestMemoryCredentialStore()
        let passRef = SecretReference(kind: .password)
        try await credStore.saveSecret(Data("proxy-ssh-secret".utf8), for: passRef, requireTouchID: false)

        for proxyKind in [ProxyKind.socks5, ProxyKind.http] {
            let proxyServer = try await LoopbackTunnelProxy.start(
                mode: proxyKind,
                targetHost: "127.0.0.1",
                targetPort: server.port
            )
            let profile = ConnectionProfile(
                name: "Proxied \(proxyKind.rawValue)",
                protocolType: .sftp,
                host: "127.0.0.1",
                port: server.port,
                username: "proxied",
                authMethod: .password,
                passwordRef: passRef,
                proxy: ProxyConfiguration(kind: proxyKind, host: "127.0.0.1", port: proxyServer.port)
            )
            let client = SSHClientService(
                profile: profile,
                credentialStore: credStore,
                hostTrustStore: HostTrustStore(backingStore: TestMemoryHostTrustBacking())
            ) { _ in true }
            let sftp = SFTPService(profile: profile, sshClient: client)
            try await sftp.connect()
            try await sftp.createDirectory(at: RemotePath(rawValue: "/via-\(proxyKind.rawValue)"))
            try await sftp.disconnect(policy: .cancelAllTransfers)
            await proxyServer.stop()
        }
        await server.stop()
    }
}
