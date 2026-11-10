import Foundation
import NIOCore
import NIOPosix
import NIOSSH
import SparkleCore
import SparkleNetworking

/// Manages active SSH local TCP port forwarding listeners (`DirectTCPIP` channels).
public actor PortForwardingManager {
    public struct ActiveTunnel: Identifiable, Sendable {
        public let id: UUID
        public let rule: PortForwardingRule
        public let listeningPort: Int
    }

    private struct RunningListener {
        let rule: PortForwardingRule
        let serverChannel: Channel
        let group: MultiThreadedEventLoopGroup
        let registry: TunnelChannelRegistry
    }

    private var listeners: [UUID: RunningListener] = [:]

    public init() {}

    public func activeTunnels() -> [ActiveTunnel] {
        listeners.map { ActiveTunnel(id: $0.key, rule: $0.value.rule, listeningPort: $0.value.rule.bindPort) }
    }

    public func startLocalForward(rule: PortForwardingRule, sshClient: SSHClientService) async throws -> ActiveTunnel {
        guard rule.direction == .local else {
            throw AppError.unsupportedCapability("Remote tunnel initiation requires server global request negotiation")
        }
        await stopTunnel(id: rule.id)

        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let registry = TunnelChannelRegistry()
        let bootstrap = Self.makeServerBootstrap(group: group, rule: rule, sshClient: sshClient, registry: registry)
        let serverChannel = try await bootstrap.bind(host: rule.bindHost, port: rule.bindPort).get()
        let actualPort = serverChannel.localAddress?.port ?? rule.bindPort
        var updatedRule = rule
        updatedRule.bindPort = actualPort
        listeners[rule.id] = RunningListener(
            rule: updatedRule,
            serverChannel: serverChannel,
            group: group,
            registry: registry
        )
        return ActiveTunnel(id: rule.id, rule: updatedRule, listeningPort: actualPort)
    }

    public func stopTunnel(id: UUID) async {
        guard let listener = listeners.removeValue(forKey: id) else { return }
        try? await listener.serverChannel.close().get()
        await listener.registry.closeAll()
        try? await listener.group.shutdownGracefully()
    }

    public func stopAll() async {
        let ids = Array(listeners.keys)
        for id in ids {
            await stopTunnel(id: id)
        }
    }

    private static func makeServerBootstrap(
        group: MultiThreadedEventLoopGroup,
        rule: PortForwardingRule,
        sshClient: SSHClientService,
        registry: TunnelChannelRegistry
    ) -> ServerBootstrap {
        ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 128)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { inboundChannel in
                guard let remoteAddress = inboundChannel.remoteAddress else {
                    return inboundChannel.eventLoop.makeFailedFuture(AppError.notConnected)
                }
                registry.register(inboundChannel)
                let promise = inboundChannel.eventLoop.makePromise(of: Void.self)
                Task {
                    do {
                        let sshChild = try await sshClient.openDirectTCPIPChannel(
                            targetHost: rule.targetHost,
                            targetPort: rule.targetPort,
                            originatorAddress: remoteAddress
                        ) { sshChildChannel in
                            sshChildChannel.eventLoop.makeCompletedFuture {
                                try sshChildChannel.pipeline.syncOperations.addHandler(SSHChannelByteWrapper())
                                try sshChildChannel.pipeline.syncOperations.addHandler(
                                    TunnelGlueHandler(peerChannel: inboundChannel)
                                )
                            }
                        }
                        registry.register(sshChild)
                        try await inboundChannel.eventLoop.submit {
                            try inboundChannel.pipeline.syncOperations.addHandler(
                                TunnelGlueHandler(peerChannel: sshChild)
                            )
                        }.get()
                        promise.succeed(())
                    } catch {
                        promise.fail(error)
                    }
                }
                return promise.futureResult
            }
    }
}

private final class TunnelChannelRegistry:
    @unchecked Sendable { // JUSTIFICATION: NSLock serializes channel tracking across teardown.
    private let lock = NSLock()
    private var channels: [ObjectIdentifier: Channel] = [:]

    func register(_ channel: Channel) {
        let id = ObjectIdentifier(channel)
        lock.lock()
        channels[id] = channel
        lock.unlock()
        channel.closeFuture.whenComplete { [weak self] _ in
            self?.remove(id: id)
        }
    }

    func closeAll() async {
        for channel in activeChannels() where channel.isActive {
            try? await channel.close().get()
        }
    }

    private func remove(id: ObjectIdentifier) {
        lock.lock()
        channels.removeValue(forKey: id)
        lock.unlock()
    }

    private func activeChannels() -> [Channel] {
        lock.lock()
        defer { lock.unlock() }
        return Array(channels.values)
    }
}

private final class SSHChannelByteWrapper: ChannelDuplexHandler {
    typealias InboundIn = SSHChannelData
    typealias InboundOut = ByteBuffer
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = SSHChannelData

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let sshData = unwrapInboundIn(data)
        if case .byteBuffer(let buffer) = sshData.data {
            context.fireChannelRead(wrapInboundOut(buffer))
        }
    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let buffer = unwrapOutboundIn(data)
        context.write(wrapOutboundOut(SSHChannelData(type: .channel, data: .byteBuffer(buffer))), promise: promise)
    }
}

private final class TunnelGlueHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer

    private let peerChannel: Channel

    init(peerChannel: Channel) {
        self.peerChannel = peerChannel
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buffer = unwrapInboundIn(data)
        guard peerChannel.isActive else { return }
        peerChannel.writeAndFlush(buffer, promise: nil)
    }

    func channelInactive(context: ChannelHandlerContext) {
        if peerChannel.isActive {
            peerChannel.close(promise: nil)
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
        if peerChannel.isActive {
            peerChannel.close(promise: nil)
        }
    }
}
