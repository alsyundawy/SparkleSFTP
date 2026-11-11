import Foundation
import NIOCore
import NIOPosix
import SparkleCore
import SparkleNetworking

/// Lightweight loopback SOCKS5 (no-auth) & HTTP CONNECT test proxy relaying raw TCP streams.
final class LoopbackTunnelProxy {
    private let group: MultiThreadedEventLoopGroup
    private var serverChannel: Channel?
    let port: Int

    private init(port: Int, serverChannel: Channel, group: MultiThreadedEventLoopGroup) {
        self.port = port
        self.serverChannel = serverChannel
        self.group = group
    }

    static func start(mode: ProxyKind, targetHost: String, targetPort: Int) async throws -> LoopbackTunnelProxy {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { clientChannel in
                clientChannel.pipeline.addHandler(
                    LoopbackProxyHandler(
                        mode: mode,
                        targetHost: targetHost,
                        targetPort: targetPort,
                        group: group
                    )
                )
            }
        let channel = try await bootstrap.bind(host: "127.0.0.1", port: 0).get()
        return LoopbackTunnelProxy(port: channel.localAddress?.port ?? 0, serverChannel: channel, group: group)
    }

    func stop() async {
        try? await serverChannel?.close().get()
        serverChannel = nil
        try? await group.shutdownGracefully()
    }
}

private final class LoopbackProxyHandler:
    ChannelInboundHandler,
    @unchecked Sendable { // JUSTIFICATION: Single EventLoop channel owns handshake state.
    typealias InboundIn = ByteBuffer

    private let mode: ProxyKind
    private let targetHost: String
    private let targetPort: Int
    private let group: MultiThreadedEventLoopGroup
    private var stage = 0
    private var buffer = ByteBufferAllocator().buffer(capacity: 256)
    private var upstreamChannel: Channel?

    init(mode: ProxyKind, targetHost: String, targetPort: Int, group: MultiThreadedEventLoopGroup) {
        self.mode = mode
        self.targetHost = targetHost
        self.targetPort = targetPort
        self.group = group
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var inbound = unwrapInboundIn(data)
        if let upstreamChannel {
            upstreamChannel.writeAndFlush(inbound, promise: nil)
            return
        }
        buffer.writeBuffer(&inbound)

        switch mode {
        case .socks5 where stage == 0:
            guard buffer.readableBytes >= 3 else { return }
            _ = buffer.readBytes(length: buffer.readableBytes)
            stage = 1
            var reply = context.channel.allocator.buffer(capacity: 2)
            reply.writeBytes([0x05, 0x00])
            context.writeAndFlush(NIOAny(reply), promise: nil)

        case .socks5:
            guard buffer.readableBytes >= 7 else { return }
            _ = buffer.readBytes(length: buffer.readableBytes)
            let targetPort = targetPort
            dialTarget(clientChannel: context.channel) { channel in
                var reply = channel.allocator.buffer(capacity: 10)
                reply.writeBytes([0x05, 0x00, 0x00, 0x01, 127, 0, 0, 1])
                reply.writeInteger(UInt16(targetPort))
                channel.writeAndFlush(reply, promise: nil)
            }

        case .http:
            let bytes = Data(buffer.readableBytesView)
            guard bytes.range(of: Data("\r\n\r\n".utf8)) != nil else { return }
            _ = buffer.readBytes(length: buffer.readableBytes)
            dialTarget(clientChannel: context.channel) { channel in
                let text = "HTTP/1.1 200 Connection Established\r\n\r\n"
                var reply = channel.allocator.buffer(capacity: text.utf8.count)
                reply.writeString(text)
                channel.writeAndFlush(reply, promise: nil)
            }

        case .none:
            break
        }
    }

    private func dialTarget(
        clientChannel: Channel,
        sendEstablishedReply: @escaping @Sendable (Channel) -> Void
    ) {
        let upstreamGlue = TunnelGlueHandler(peerChannel: clientChannel, waitForPeerActivation: true)
        let bootstrap = ClientBootstrap(group: group)
            .channelOption(ChannelOptions.autoRead, value: false)
            .channelInitializer { upstream in
                upstream.eventLoop.makeCompletedFuture {
                    try upstream.pipeline.syncOperations.addHandler(upstreamGlue)
                }
            }

        bootstrap.connect(host: targetHost, port: targetPort).whenComplete { result in
            switch result {
            case let .success(upstream):
                clientChannel.eventLoop.execute {
                    self.upstreamChannel = upstream
                    sendEstablishedReply(clientChannel)
                    _ = upstream.setOption(ChannelOptions.autoRead, value: true)
                    upstreamGlue.markPeerReady()
                }
            case .failure:
                clientChannel.close(promise: nil)
            }
        }
    }
}
