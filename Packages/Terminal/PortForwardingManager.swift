import Foundation
import NIOCore
import NIOPosix
import NIOSSH
import SparkleCore
import SparkleNetworking

/// Manages active SSH local (`DirectTCPIP`) and remote (`tcpip-forward`) TCP port forwarding listeners.
public actor PortForwardingManager {
    public struct ActiveTunnel: Identifiable, Sendable {
        public let id: UUID
        public let rule: PortForwardingRule
        public let listeningPort: Int
    }

    private struct RunningLocalListener {
        let rule: PortForwardingRule
        let serverChannel: Channel
        let group: MultiThreadedEventLoopGroup
        let registry: TunnelChannelRegistry
    }

    private struct RunningRemoteForward {
        let rule: PortForwardingRule
        let sshClient: SSHClientService
    }

    private var localListeners: [UUID: RunningLocalListener] = [:]
    private var remoteForwards: [UUID: RunningRemoteForward] = [:]

    public init() {}

    public func activeTunnels() -> [ActiveTunnel] {
        let local = localListeners.map {
            ActiveTunnel(id: $0.key, rule: $0.value.rule, listeningPort: $0.value.rule.bindPort)
        }
        let remote = remoteForwards.map {
            ActiveTunnel(id: $0.key, rule: $0.value.rule, listeningPort: $0.value.rule.bindPort)
        }
        return (local + remote).sorted { $0.rule.name < $1.rule.name }
    }

    public func startForward(rule: PortForwardingRule, sshClient: SSHClientService) async throws -> ActiveTunnel {
        switch rule.direction {
        case .local:
            return try await startLocalForward(rule: rule, sshClient: sshClient)
        case .remote:
            await stopTunnel(id: rule.id)
            let actualPort = try await sshClient.startRemotePortForward(
                bindHost: rule.bindHost,
                bindPort: rule.bindPort,
                targetHost: rule.targetHost,
                targetPort: rule.targetPort
            )
            var updatedRule = rule
            updatedRule.bindPort = actualPort
            remoteForwards[rule.id] = RunningRemoteForward(rule: updatedRule, sshClient: sshClient)
            return ActiveTunnel(id: rule.id, rule: updatedRule, listeningPort: actualPort)
        }
    }

    public func startLocalForward(rule: PortForwardingRule, sshClient: SSHClientService) async throws -> ActiveTunnel {
        guard rule.direction == .local else {
            return try await startForward(rule: rule, sshClient: sshClient)
        }
        await stopTunnel(id: rule.id)

        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let registry = TunnelChannelRegistry()
        let bootstrap = Self.makeServerBootstrap(group: group, rule: rule, sshClient: sshClient, registry: registry)
        let serverChannel = try await bootstrap.bind(host: rule.bindHost, port: rule.bindPort).get()
        let actualPort = serverChannel.localAddress?.port ?? rule.bindPort
        var updatedRule = rule
        updatedRule.bindPort = actualPort
        localListeners[rule.id] = RunningLocalListener(
            rule: updatedRule,
            serverChannel: serverChannel,
            group: group,
            registry: registry
        )
        return ActiveTunnel(id: rule.id, rule: updatedRule, listeningPort: actualPort)
    }

    public func stopTunnel(id: UUID) async {
        if let listener = localListeners.removeValue(forKey: id) {
            await listener.registry.closeAll()
            await SSHClientService.closeChannelAndShutdownGroup(listener.serverChannel, group: listener.group)
        }
        if let remote = remoteForwards.removeValue(forKey: id) {
            await remote.sshClient.stopRemotePortForward(
                bindHost: remote.rule.bindHost,
                bindPort: remote.rule.bindPort
            )
        }
    }

    public func stopAll() async {
        let ids = Array(localListeners.keys) + Array(remoteForwards.keys)
        await withTaskGroup(of: Void.self) { group in
            for id in ids {
                group.addTask {
                    await self.stopTunnel(id: id)
                }
            }
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
