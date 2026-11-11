import Crypto
import Foundation
import NIOCore
import NIOPosix
import NIOSSH
import SparkleCore
import SparkleSecurity

public struct SSHCommandOutput: Sendable, Equatable {
    public let exitCode: Int
    public let stdout: String
    public let stderr: String
}

/// Active SSH PTY channel handle supporting writes, terminal resize, inbound stream, and explicit close.
public final class SSHPTYChannel: @unchecked Sendable { // JUSTIFICATION: I/O executes on channel.eventLoop.
    public let outputStream: AsyncStream<[UInt8]>
    private let channel: Channel
    private let onTeardown: @Sendable () -> Void
    private var isClosed = false
    private let lock = NSLock()

    init(channel: Channel, outputStream: AsyncStream<[UInt8]>, onTeardown: @escaping @Sendable () -> Void) {
        self.channel = channel
        self.outputStream = outputStream
        self.onTeardown = onTeardown
    }

    public func write(bytes: ArraySlice<UInt8>) {
        var buffer = channel.allocator.buffer(capacity: bytes.count)
        buffer.writeBytes(bytes)
        let payload = SSHChannelData(type: .channel, data: .byteBuffer(buffer))
        channel.eventLoop.execute { [channel] in
            channel.writeAndFlush(payload, promise: nil)
        }
    }

    public func resize(cols: Int, rows: Int) {
        let request = SSHChannelRequestEvent.WindowChangeRequest(
            terminalCharacterWidth: max(1, cols),
            terminalRowHeight: max(1, rows),
            terminalPixelWidth: 0,
            terminalPixelHeight: 0
        )
        channel.eventLoop.execute { [channel] in
            channel.triggerUserOutboundEvent(request, promise: nil)
        }
    }

    public func close() {
        lock.lock()
        guard !isClosed else {
            lock.unlock()
            return
        }
        isClosed = true
        lock.unlock()

        onTeardown()
        channel.close(promise: nil)
    }

    deinit {
        close()
    }
}

/// Interactive prompt descriptor when connecting with uncached password or 2FA challenge (`TASK-096`).
public struct CredentialPromptRequest: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let host: String
    public let port: Int
    public let username: String
    public let authMethod: AuthMethod
    public let promptTitle: String

    public init(
        id: UUID = UUID(),
        host: String,
        port: Int,
        username: String,
        authMethod: AuthMethod,
        promptTitle: String
    ) {
        self.id = id
        self.host = host
        self.port = port
        self.username = username
        self.authMethod = authMethod
        self.promptTitle = promptTitle
    }
}

/// Manages an authenticated `apple/swift-nio-ssh` transport session, TOFU host verification,
/// SFTP/exec/PTY child channels, proxy/bastion jumps, and port forwarding (`DirectTCPIP` / `tcpip-forward`).
public actor SSHClientService {
    public typealias HostTrustPromptHandler = @Sendable (HostKeyChallenge) async -> Bool
    public typealias CredentialPromptHandler = @Sendable (CredentialPromptRequest) async -> String?
    public typealias JumpProfileResolver = @Sendable (UUID) async -> ConnectionProfile?

    public nonisolated let profile: ConnectionProfile
    let credentialStore: any CredentialStoreProtocol
    let hostTrustStore: any HostTrustStoreProtocol
    let hostTrustPrompt: HostTrustPromptHandler
    let credentialPrompt: CredentialPromptHandler?
    let jumpProfileResolver: JumpProfileResolver?
    let stallTimeoutSeconds: Int
    let remoteForwardMap = RemoteForwardTargetMap()

    private var eventLoopGroup: MultiThreadedEventLoopGroup?
    var rootChannel: Channel?
    private var jumpTunnel: SSHJumpTunnelHandle?
    public private(set) var connectionState: ConnectionState = .disconnected

    public init(
        profile: ConnectionProfile,
        credentialStore: any CredentialStoreProtocol,
        hostTrustStore: any HostTrustStoreProtocol,
        stallTimeoutSeconds: Int = 30,
        hostTrustPrompt: @escaping HostTrustPromptHandler = { _ in false },
        credentialPrompt: CredentialPromptHandler? = nil,
        jumpProfileResolver: JumpProfileResolver? = nil
    ) {
        self.profile = profile
        self.credentialStore = credentialStore
        self.hostTrustStore = hostTrustStore
        self.stallTimeoutSeconds = stallTimeoutSeconds
        self.hostTrustPrompt = hostTrustPrompt
        self.credentialPrompt = credentialPrompt
        self.jumpProfileResolver = jumpProfileResolver
    }

    public func connect() async throws {
        try await connectInternal(visitedJumpIDs: [])
    }

    func connectInternal(visitedJumpIDs: Set<UUID>) async throws {
        if case .connected = connectionState, rootChannel != nil {
            return
        }
        connectionState = .connecting

        let password = try await resolvePasswordSecret()
        let privateKey = try await resolvePrivateKey()
        let activeJump = try await openBastionIfNeeded(visitedJumpIDs: visitedJumpIDs)

        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let handshakeBox = SSHHandshakeStateBox(promise: group.next().makePromise(of: Void.self))
        let endpoint = resolveEndpoint(activeJump: activeJump)
        let bootstrap = makeBootstrap(
            group: group,
            password: password,
            privateKey: privateKey,
            handshakeBox: handshakeBox,
            includeProxyHandler: endpoint.useProxy
        )

        try await performSSHConnect(
            SSHConnectAttempt(
                bootstrap: bootstrap,
                group: group,
                handshakeBox: handshakeBox,
                endpoint: endpoint,
                activeJump: activeJump
            )
        )
    }

    private func resolvePasswordSecret() async throws -> String? {
        if let stored = try await loadOptionalSecret(
            ref: profile.passwordRef,
            prompt: "Unlock SSH password for \(profile.name)"
        ) {
            return stored
        }
        let needsPrompt = profile.authMethod == .password || profile.authMethod == .keyboardInteractive
        guard needsPrompt, let credentialPrompt else { return nil }
        let promptReq = CredentialPromptRequest(
            host: profile.host,
            port: profile.port,
            username: profile.username,
            authMethod: profile.authMethod,
            promptTitle: "Enter \(profile.authMethod.rawValue) secret for \(profile.username)@\(profile.host)"
        )
        return await credentialPrompt(promptReq)
    }

    private func openBastionIfNeeded(visitedJumpIDs: Set<UUID>) async throws -> SSHJumpTunnelHandle? {
        guard let jumpID = profile.jumpHostProfileID else { return nil }
        guard !visitedJumpIDs.contains(jumpID) else {
            throw AppError.invalidConfiguration("Circular SSH Jump Host cycle detected")
        }
        guard let bastionProfile = await jumpProfileResolver?(jumpID) else {
            throw AppError.invalidConfiguration("Configured SSH Jump Host profile was not found")
        }
        return try await Self.openJumpTunnel(
            request: SSHJumpTunnelRequest(
                bastionProfile: bastionProfile,
                targetHost: profile.host,
                targetPort: profile.port,
                credentialStore: credentialStore,
                hostTrustStore: hostTrustStore,
                hostTrustPrompt: hostTrustPrompt,
                credentialPrompt: credentialPrompt,
                jumpProfileResolver: jumpProfileResolver,
                visitedJumpIDs: visitedJumpIDs.union([profile.id])
            )
        )
    }

    private struct SSHConnectEndpoint {
        let host: String
        let port: Int
        let useProxy: Bool
    }

    private struct SSHConnectAttempt {
        let bootstrap: ClientBootstrap
        let group: MultiThreadedEventLoopGroup
        let handshakeBox: SSHHandshakeStateBox
        let endpoint: SSHConnectEndpoint
        let activeJump: SSHJumpTunnelHandle?
    }

    private func resolveEndpoint(activeJump: SSHJumpTunnelHandle?) -> SSHConnectEndpoint {
        if let activeJump {
            return SSHConnectEndpoint(host: "127.0.0.1", port: activeJump.listeningPort, useProxy: false)
        }
        if profile.proxy.kind != .none, !profile.proxy.host.isEmpty {
            return SSHConnectEndpoint(host: profile.proxy.host, port: profile.proxy.port, useProxy: true)
        }
        return SSHConnectEndpoint(host: profile.host, port: profile.port, useProxy: false)
    }

    private func performSSHConnect(_ attempt: SSHConnectAttempt) async throws {
        var connectedChannel: Channel?
        let timeoutSeconds = stallTimeoutSeconds
        let targetHost = profile.host
        do {
            let channel = try await attempt.bootstrap.connect(
                host: attempt.endpoint.host,
                port: attempt.endpoint.port
            ).get()
            connectedChannel = channel
            let handshakeBox = attempt.handshakeBox
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await withTaskCancellationHandler {
                        try await handshakeBox.futureResult.get()
                    } onCancel: {
                        let timeoutError = AppError.connectionTimeout(host: targetHost, seconds: timeoutSeconds)
                        handshakeBox.failHandshake(defaultError: timeoutError)
                        channel.close(promise: nil)
                    }
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(timeoutSeconds))
                    throw AppError.connectionTimeout(host: targetHost, seconds: timeoutSeconds)
                }
                _ = try await group.next()
                group.cancelAll()
            }
            jumpTunnel = attempt.activeJump
            eventLoopGroup = attempt.group
            rootChannel = channel
            connectionState = .connected(connectedAt: Date())
            let connectedHost = profile.host
            let connectedPort = profile.port
            DiagnosticsLogger.network.info(
                "SSH connected to \(connectedHost, privacy: .private):\(connectedPort, privacy: .public)"
            )
        } catch {
            if let connectedChannel {
                try? await connectedChannel.close().get()
            }
            try? await attempt.group.shutdownGracefully()
            await attempt.activeJump?.stop()
            let mapped = Self.mapSSHError(error, host: profile.host, port: profile.port, authMethod: profile.authMethod)
            connectionState = .failed(mapped)
            throw mapped
        }
    }

    public func disconnect(policy _: DisconnectPolicy) async throws {
        if let channel = rootChannel {
            try? await channel.close().get()
            rootChannel = nil
        }
        if let group = eventLoopGroup {
            try? await group.shutdownGracefully()
            eventLoopGroup = nil
        }
        if let activeJump = jumpTunnel {
            jumpTunnel = nil
            await activeJump.stop()
        }
        connectionState = .disconnected
    }

    public func executeCommand(_ command: String, timeoutSeconds: Int? = nil) async throws -> SSHCommandOutput {
        guard let rootChannel else { throw AppError.notConnected }
        let timeout = timeoutSeconds ?? stallTimeoutSeconds

        return try await withThrowingTaskGroup(of: SSHCommandOutput.self) { group in
            group.addTask {
                try await Self.runExec(on: rootChannel, command: command)
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw AppError.channelStalled(reason: "Exec command timed out after \(timeout)s")
            }
            guard let first = try await group.next() else {
                throw AppError.channelStalled(reason: "Exec produced no result")
            }
            group.cancelAll()
            return first
        }
    }

    public func openSFTPBridge() async throws -> SFTPChannelBridge {
        guard let rootChannel else { throw AppError.notConnected }
        return try await Self.createSFTPBridge(on: rootChannel, timeoutSeconds: stallTimeoutSeconds)
    }

    public func openPTYChannel(
        term: String = "xterm-256color",
        cols: Int = 80,
        rows: Int = 24
    ) async throws -> SSHPTYChannel {
        guard let rootChannel else { throw AppError.notConnected }
        let (stream, continuation) = AsyncStream<[UInt8]>.makeStream(bufferingPolicy: .bufferingNewest(256))
        let channelPromise = rootChannel.eventLoop.makePromise(of: Channel.self)

        rootChannel.eventLoop.execute {
            do {
                let sshHandler = try rootChannel.pipeline.syncOperations.handler(type: NIOSSHHandler.self)
                sshHandler.createChannel(channelPromise, channelType: .session) { childChannel, channelType in
                    guard channelType == .session else {
                        return childChannel.eventLoop.makeFailedFuture(
                            AppError.protocolError(code: -1, message: "Invalid SSH channel type")
                        )
                    }
                    return childChannel.eventLoop.makeCompletedFuture {
                        let handler = SSHPTYChannelHandler(
                            term: term,
                            cols: cols,
                            rows: rows,
                            continuation: continuation
                        )
                        try childChannel.pipeline.syncOperations.addHandler(handler)
                    }
                }
            } catch {
                channelPromise.fail(error)
            }
        }

        let childChannel = try await channelPromise.futureResult.get()
        return SSHPTYChannel(channel: childChannel, outputStream: stream) {
            continuation.finish()
        }
    }
}
