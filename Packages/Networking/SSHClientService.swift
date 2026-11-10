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

/// Manages an authenticated `apple/swift-nio-ssh` transport session, TOFU host verification,
/// SFTP/exec/PTY child channels, and port forwarding (`DirectTCPIP`).
public actor SSHClientService {
    public typealias HostTrustPromptHandler = @Sendable (HostKeyChallenge) async -> Bool

    public nonisolated let profile: ConnectionProfile
    let credentialStore: any CredentialStoreProtocol
    let hostTrustStore: any HostTrustStoreProtocol
    let hostTrustPrompt: HostTrustPromptHandler
    let stallTimeoutSeconds: Int

    private var eventLoopGroup: MultiThreadedEventLoopGroup?
    private var rootChannel: Channel?
    public private(set) var connectionState: ConnectionState = .disconnected

    public init(
        profile: ConnectionProfile,
        credentialStore: any CredentialStoreProtocol,
        hostTrustStore: any HostTrustStoreProtocol,
        stallTimeoutSeconds: Int = 30,
        hostTrustPrompt: @escaping HostTrustPromptHandler = { _ in false }
    ) {
        self.profile = profile
        self.credentialStore = credentialStore
        self.hostTrustStore = hostTrustStore
        self.stallTimeoutSeconds = stallTimeoutSeconds
        self.hostTrustPrompt = hostTrustPrompt
    }

    public func connect() async throws {
        if case .connected = connectionState, rootChannel != nil {
            return
        }
        connectionState = .connecting

        let password = try await loadOptionalSecret(
            ref: profile.passwordRef,
            prompt: "Unlock SSH password for \(profile.name)"
        )
        let privateKeyPEM = try await loadOptionalSecret(
            ref: profile.privateKeyRef,
            prompt: "Unlock SSH private key for \(profile.name)"
        )

        let privateKey: NIOSSHPrivateKey?
        if let pem = privateKeyPEM, !pem.isEmpty {
            privateKey = try PrivateKeyParser.parsePrivateKey(pemString: pem)
        } else {
            privateKey = nil
        }

        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let handshakeBox = SSHHandshakeStateBox(promise: group.next().makePromise(of: Void.self))
        let bootstrap = makeBootstrap(
            group: group,
            password: password,
            privateKey: privateKey,
            handshakeBox: handshakeBox
        )

        var connectedChannel: Channel?
        do {
            let channel = try await bootstrap.connect(host: profile.host, port: profile.port).get()
            connectedChannel = channel
            try await handshakeBox.futureResult.get()
            self.eventLoopGroup = group
            self.rootChannel = channel
            self.connectionState = .connected(connectedAt: Date())
            DiagnosticsLogger.network.info(
                "SSH connected to \(self.profile.host, privacy: .private):\(self.profile.port, privacy: .public)"
            )
        } catch {
            if let connectedChannel {
                try? await connectedChannel.close().get()
            }
            try? await group.shutdownGracefully()
            let mapped = Self.mapSSHError(error, host: profile.host, port: profile.port, authMethod: profile.authMethod)
            self.connectionState = .failed(mapped)
            throw mapped
        }
    }

    public func disconnect(policy: DisconnectPolicy) async throws {
        if let channel = rootChannel {
            try? await channel.close().get()
            rootChannel = nil
        }
        if let group = eventLoopGroup {
            try? await group.shutdownGracefully()
            eventLoopGroup = nil
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
        return try await Self.createSFTPBridge(on: rootChannel)
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

    public func openDirectTCPIPChannel(
        targetHost: String,
        targetPort: Int,
        originatorAddress: SocketAddress,
        initializer: @escaping @Sendable (Channel) -> EventLoopFuture<Void>
    ) async throws -> Channel {
        guard let rootChannel else { throw AppError.notConnected }
        let promise = rootChannel.eventLoop.makePromise(of: Channel.self)
        let tcpInfo = SSHChannelType.DirectTCPIP(
            targetHost: targetHost,
            targetPort: targetPort,
            originatorAddress: originatorAddress
        )
        rootChannel.eventLoop.execute {
            do {
                let sshHandler = try rootChannel.pipeline.syncOperations.handler(type: NIOSSHHandler.self)
                sshHandler.createChannel(promise, channelType: .directTCPIP(tcpInfo)) { childChannel, _ in
                    initializer(childChannel)
                }
            } catch {
                promise.fail(error)
            }
        }
        return try await promise.futureResult.get()
    }
}
