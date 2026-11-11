import Foundation
import NIOCore
import NIOPosix
import NIOSSH
import SparkleCore

/// Active bastion tunnel listener backing SSH `ProxyJump` connections (`TASK-052` / `TASK-097`).
final class SSHJumpTunnelHandle: @unchecked Sendable { // JUSTIFICATION: Synchronizes lifecycle shutdown once.
    private let bastionClient: SSHClientService
    private let serverChannel: Channel
    private let group: MultiThreadedEventLoopGroup
    let listeningPort: Int

    init(
        bastionClient: SSHClientService,
        serverChannel: Channel,
        group: MultiThreadedEventLoopGroup,
        listeningPort: Int
    ) {
        self.bastionClient = bastionClient
        self.serverChannel = serverChannel
        self.group = group
        self.listeningPort = listeningPort
    }

    func stop() async {
        await SSHClientService.closeChannelAndShutdownGroup(serverChannel, group: nil)
        try? await bastionClient.disconnect(policy: .cancelAllTransfers)
        await SSHClientService.closeChannelAndShutdownGroup(nil, group: group)
    }
}

/// Maps server-bound remote forwarding listening ports to local destination endpoints (`TASK-099`).
final class RemoteForwardTargetMap: @unchecked Sendable { // JUSTIFICATION: NSLock protects cross-thread map state.
    private let lock = NSLock()
    private var targets: [Int: (targetHost: String, targetPort: Int)] = [:]

    func setTarget(bindPort: Int, targetHost: String, targetPort: Int) {
        lock.lock()
        targets[bindPort] = (targetHost, targetPort)
        lock.unlock()
    }

    func removeTarget(bindPort: Int) {
        lock.lock()
        targets.removeValue(forKey: bindPort)
        lock.unlock()
    }

    func target(forListeningPort port: Int) -> (targetHost: String, targetPort: Int)? {
        lock.lock()
        defer { lock.unlock() }
        return targets[port]
    }
}

struct SSHJumpTunnelRequest: Sendable {
    let bastionProfile: ConnectionProfile
    let targetHost: String
    let targetPort: Int
    let credentialStore: any CredentialStoreProtocol
    let hostTrustStore: any HostTrustStoreProtocol
    let hostTrustPrompt: SSHClientService.HostTrustPromptHandler
    let credentialPrompt: SSHClientService.CredentialPromptHandler?
    let jumpProfileResolver: SSHClientService.JumpProfileResolver?
    let visitedJumpIDs: Set<UUID>
}

extension SSHClientService {
    /// Opens an outbound `DirectTCPIP` forwarding channel over the active SSH connection.
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

    /// Requests remote TCP port forwarding (`-R`) from the SSH server via `tcpip-forward` (`TASK-099`).
    public func startRemotePortForward(
        bindHost: String,
        bindPort: Int,
        targetHost: String,
        targetPort: Int
    ) async throws -> Int {
        guard let rootChannel else { throw AppError.notConnected }
        let promise = rootChannel.eventLoop.makePromise(of: GlobalRequest.TCPForwardingResponse?.self)

        rootChannel.eventLoop.execute {
            do {
                let sshHandler = try rootChannel.pipeline.syncOperations.handler(type: NIOSSHHandler.self)
                sshHandler.sendTCPForwardingRequest(.listen(host: bindHost, port: bindPort), promise: promise)
            } catch {
                promise.fail(error)
            }
        }

        let timeout = stallTimeoutSeconds
        let response = try await withThrowingTaskGroup(
            of: GlobalRequest.TCPForwardingResponse?.self,
            returning: GlobalRequest.TCPForwardingResponse?.self
        ) { taskGroup in
            taskGroup.addTask {
                try await withTaskCancellationHandler {
                    try await promise.futureResult.get()
                } onCancel: {
                    promise.fail(CancellationError())
                }
            }
            taskGroup.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw AppError.channelStalled(reason: "Remote port forward request timed out after \(timeout)s")
            }
            guard let first = try await taskGroup.next() else {
                taskGroup.cancelAll()
                return nil
            }
            taskGroup.cancelAll()
            return first
        }
        let actualPort = response?.boundPort ?? bindPort
        remoteForwardMap.setTarget(bindPort: actualPort, targetHost: targetHost, targetPort: targetPort)
        return actualPort
    }

    /// Cancels remote TCP port forwarding (`cancel-tcpip-forward`) on the connected SSH server.
    public func stopRemotePortForward(bindHost: String, bindPort: Int) async {
        remoteForwardMap.removeTarget(bindPort: bindPort)
        guard let rootChannel, rootChannel.isActive else { return }
        let promise = rootChannel.eventLoop.makePromise(of: GlobalRequest.TCPForwardingResponse?.self)

        rootChannel.eventLoop.execute {
            do {
                let sshHandler = try rootChannel.pipeline.syncOperations.handler(type: NIOSSHHandler.self)
                sshHandler.sendTCPForwardingRequest(.cancel(host: bindHost, port: bindPort), promise: promise)
            } catch {
                promise.fail(error)
            }
        }

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                _ = try? await withTaskCancellationHandler {
                    try await promise.futureResult.get()
                } onCancel: {
                    promise.fail(CancellationError())
                }
            }
            group.addTask { try? await Task.sleep(for: .seconds(3)) }
            _ = await group.next()
            group.cancelAll()
        }
    }

    static func openJumpTunnel(request: SSHJumpTunnelRequest) async throws -> SSHJumpTunnelHandle {
        let bastion = SSHClientService(
            profile: request.bastionProfile,
            credentialStore: request.credentialStore,
            hostTrustStore: request.hostTrustStore,
            hostTrustPrompt: request.hostTrustPrompt,
            credentialPrompt: request.credentialPrompt,
            jumpProfileResolver: request.jumpProfileResolver
        )
        try await bastion.connectInternal(visitedJumpIDs: request.visitedJumpIDs)

        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        do {
            let bootstrap = makeJumpServerBootstrap(
                group: group,
                bastion: bastion,
                targetHost: request.targetHost,
                targetPort: request.targetPort
            )
            let serverChannel = try await bootstrap.bind(host: "127.0.0.1", port: 0).get()
            let port = serverChannel.localAddress?.port ?? 0
            return SSHJumpTunnelHandle(
                bastionClient: bastion,
                serverChannel: serverChannel,
                group: group,
                listeningPort: port
            )
        } catch {
            await SSHClientService.closeChannelAndShutdownGroup(nil, group: group)
            try? await bastion.disconnect(policy: .cancelAllTransfers)
            throw error
        }
    }

    private static func makeJumpServerBootstrap(
        group: MultiThreadedEventLoopGroup,
        bastion: SSHClientService,
        targetHost: String,
        targetPort: Int
    ) -> ServerBootstrap {
        ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 16)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.autoRead, value: false)
            .childChannelInitializer { inboundChannel in
                guard let originator = inboundChannel.remoteAddress else {
                    return inboundChannel.eventLoop.makeFailedFuture(AppError.notConnected)
                }
                return bridgeJumpConnection(
                    inboundChannel: inboundChannel,
                    originator: originator,
                    bastion: bastion,
                    targetHost: targetHost,
                    targetPort: targetPort
                )
            }
    }

    private static func bridgeJumpConnection(
        inboundChannel: Channel,
        originator: SocketAddress,
        bastion: SSHClientService,
        targetHost: String,
        targetPort: Int
    ) -> EventLoopFuture<Void> {
        let promise = inboundChannel.eventLoop.makePromise(of: Void.self)
        let sshGlue = TunnelGlueHandler(peerChannel: inboundChannel, waitForPeerActivation: true)
        Task {
            do {
                let remoteChannel = try await bastion.openDirectTCPIPChannel(
                    targetHost: targetHost,
                    targetPort: targetPort,
                    originatorAddress: originator
                ) { sshChild in
                    sshChild.eventLoop.makeCompletedFuture {
                        try sshChild.pipeline.syncOperations.addHandler(SSHChannelByteWrapper())
                        try sshChild.pipeline.syncOperations.addHandler(sshGlue)
                    }
                }
                attachJumpRelay(
                    inboundChannel: inboundChannel,
                    remoteChannel: remoteChannel,
                    sshGlue: sshGlue,
                    promise: promise
                )
            } catch {
                inboundChannel.eventLoop.execute {
                    promise.fail(error)
                }
            }
        }
        return promise.futureResult
    }

    private static func attachJumpRelay(
        inboundChannel: Channel,
        remoteChannel: Channel,
        sshGlue: TunnelGlueHandler,
        promise: EventLoopPromise<Void>
    ) {
        inboundChannel.eventLoop.execute {
            do {
                let inboundGlue = TunnelGlueHandler(
                    peerChannel: remoteChannel,
                    onChannelActive: {
                        _ = inboundChannel.setOption(ChannelOptions.autoRead, value: true)
                        sshGlue.markPeerReady()
                    }
                )
                try inboundChannel.pipeline.syncOperations.addHandler(inboundGlue)
                inboundChannel.closeFuture.whenComplete { _ in
                    remoteChannel.close(promise: nil)
                }
                promise.succeed(())
            } catch {
                remoteChannel.close(promise: nil)
                promise.fail(error)
            }
        }
    }

    static func handleInboundChildChannel(
        _ childChannel: Channel,
        channelType: SSHChannelType,
        remoteForwardMap: RemoteForwardTargetMap,
        group: MultiThreadedEventLoopGroup
    ) -> EventLoopFuture<Void> {
        guard case let .forwardedTCPIP(info) = channelType,
              let target = remoteForwardMap.target(forListeningPort: info.listeningPort)
        else {
            return childChannel.eventLoop.makeFailedFuture(
                AppError.protocolError(code: -1, message: "Unexpected inbound SSH channel")
            )
        }

        let promise = childChannel.eventLoop.makePromise(of: Void.self)
        let bootstrap = ClientBootstrap(group: group)
            .channelOption(ChannelOptions.autoRead, value: false)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(IPPROTO_TCP), TCP_NODELAY), value: 1)
            .channelInitializer { localChannel in
                localChannel.eventLoop.makeCompletedFuture {
                    try localChannel.pipeline.syncOperations.addHandler(TunnelGlueHandler(peerChannel: childChannel))
                }
            }

        bootstrap.connect(host: target.targetHost, port: target.targetPort).whenComplete { result in
            switch result {
            case let .success(localChannel):
                childChannel.eventLoop.execute {
                    do {
                        try childChannel.pipeline.syncOperations.addHandler(SSHChannelByteWrapper())
                        try childChannel.pipeline.syncOperations.addHandler(
                            TunnelGlueHandler(peerChannel: localChannel)
                        )
                        promise.succeed(())
                        _ = localChannel.setOption(ChannelOptions.autoRead, value: true)
                    } catch {
                        localChannel.close(promise: nil)
                        promise.fail(error)
                    }
                }
            case let .failure(error):
                promise.fail(error)
            }
        }
        return promise.futureResult
    }
}
