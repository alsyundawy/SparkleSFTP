import Foundation
import NIOCore
import NIOPosix
import NIOSSH
import SparkleNetworking
import SparkleSecurity

final class LoopbackSSHServer {
    private let group: MultiThreadedEventLoopGroup
    private var serverChannel: Channel?
    let port: Int

    init(port: Int, serverChannel: Channel, group: MultiThreadedEventLoopGroup) {
        self.port = port
        self.serverChannel = serverChannel
        self.group = group
    }

    static func start(
        hostKey: NIOSSHPrivateKey,
        username: String,
        password: String?,
        authorizedPublicKeyFingerprint: String?,
        virtualFS: LoopbackSFTPVirtualFS
    ) async throws -> LoopbackSSHServer {
        try await bindServer(
            hostKey: hostKey,
            username: username,
            password: password,
            authorizedPublicKeyFingerprint: authorizedPublicKeyFingerprint,
            virtualFS: virtualFS
        )
    }

    private static func bindServer(
        hostKey: NIOSSHPrivateKey,
        username: String,
        password: String?,
        authorizedPublicKeyFingerprint: String?,
        virtualFS: LoopbackSFTPVirtualFS
    ) async throws -> LoopbackSSHServer {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let authDelegate = LoopbackServerUserAuthDelegate(
            expectedUsername: username,
            expectedPassword: password,
            expectedPublicKeyFingerprint: authorizedPublicKeyFingerprint
        )
        let globalDelegate = LoopbackGlobalRequestDelegate()

        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    let config = SSHServerConfiguration(
                        hostKeys: [hostKey],
                        userAuthDelegate: authDelegate,
                        globalRequestDelegate: globalDelegate
                    )
                    let sshHandler = NIOSSHHandler(
                        role: .server(config),
                        allocator: channel.allocator,
                        inboundChildChannelInitializer: { childChannel, channelType in
                            Self.initializeChildChannel(
                                childChannel,
                                type: channelType,
                                virtualFS: virtualFS,
                                group: group
                            )
                        }
                    )
                    try channel.pipeline.syncOperations.addHandler(sshHandler)
                }
            }

        let channel = try await bootstrap.bind(host: "127.0.0.1", port: 0).get()
        let boundPort = channel.localAddress?.port ?? 0
        return LoopbackSSHServer(port: boundPort, serverChannel: channel, group: group)
    }

    private static func initializeChildChannel(
        _ childChannel: Channel,
        type: SSHChannelType,
        virtualFS: LoopbackSFTPVirtualFS,
        group: MultiThreadedEventLoopGroup
    ) -> EventLoopFuture<Void> {
        switch type {
        case .session:
            return childChannel.eventLoop.makeCompletedFuture {
                try childChannel.pipeline.syncOperations.addHandler(LoopbackSFTPChannelHandler(virtualFS: virtualFS))
            }
        case let .directTCPIP(info) where info.targetPort != 9999:
            let promise = childChannel.eventLoop.makePromise(of: Void.self)
            let clientBootstrap = ClientBootstrap(group: group)
                .channelOption(ChannelOptions.autoRead, value: false)
                .channelInitializer { targetChannel in
                    targetChannel.eventLoop.makeCompletedFuture {
                        try targetChannel.pipeline.syncOperations.addHandler(
                            TunnelGlueHandler(peerChannel: childChannel)
                        )
                    }
                }
            clientBootstrap.connect(host: info.targetHost, port: info.targetPort).whenComplete { result in
                switch result {
                case let .success(targetChannel):
                    childChannel.eventLoop.execute {
                        do {
                            try childChannel.pipeline.syncOperations.addHandler(SSHChannelByteWrapper())
                            try childChannel.pipeline.syncOperations.addHandler(
                                TunnelGlueHandler(peerChannel: targetChannel)
                            )
                            promise.succeed(())
                            _ = targetChannel.setOption(ChannelOptions.autoRead, value: true)
                        } catch {
                            targetChannel.close(promise: nil)
                            promise.fail(error)
                        }
                    }
                case let .failure(error):
                    promise.fail(error)
                }
            }
            return promise.futureResult
        case .directTCPIP:
            return childChannel.eventLoop.makeCompletedFuture {
                try childChannel.pipeline.syncOperations.addHandler(LoopbackDirectTCPIPEchoHandler())
            }
        default:
            return childChannel.eventLoop.makeSucceededVoidFuture()
        }
    }

    func stop() async {
        try? await serverChannel?.close().get()
        serverChannel = nil
        try? await group.shutdownGracefully()
    }
}

private final class LoopbackServerUserAuthDelegate:
    NIOSSHServerUserAuthenticationDelegate,
    @unchecked Sendable { // JUSTIFICATION: Immutable test credentials.
    let expectedUsername: String
    let expectedPassword: String?
    let expectedPublicKeyFingerprint: String?

    init(expectedUsername: String, expectedPassword: String?, expectedPublicKeyFingerprint: String?) {
        self.expectedUsername = expectedUsername
        self.expectedPassword = expectedPassword
        self.expectedPublicKeyFingerprint = expectedPublicKeyFingerprint
    }

    var supportedAuthenticationMethods: NIOSSHAvailableUserAuthenticationMethods {
        [.password, .publicKey]
    }

    func requestReceived(
        request: NIOSSHUserAuthenticationRequest,
        responsePromise: EventLoopPromise<NIOSSHUserAuthenticationOutcome>
    ) {
        guard request.username == expectedUsername else {
            responsePromise.succeed(.failure)
            return
        }
        switch request.request {
        case let .password(passwordAuth):
            responsePromise.succeed(passwordAuth.password == expectedPassword ? .success : .failure)
        case let .publicKey(publicKeyAuth):
            let actualFP = SSHKeyFingerprint.sha256(for: publicKeyAuth.publicKey)
            responsePromise.succeed(actualFP == expectedPublicKeyFingerprint ? .success : .failure)
        default:
            responsePromise.succeed(.failure)
        }
    }
}

private final class LoopbackSFTPChannelHandler: ChannelInboundHandler {
    typealias InboundIn = SSHChannelData

    private let virtualFS: LoopbackSFTPVirtualFS
    private var inboundBuffer = ByteBufferAllocator().buffer(capacity: 4096)
    private var isSFTP = false

    init(virtualFS: LoopbackSFTPVirtualFS) {
        self.virtualFS = virtualFS
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if let subsystem = event as? SSHChannelRequestEvent.SubsystemRequest, subsystem.subsystem == "sftp" {
            isSFTP = true
            context.fireUserInboundEventTriggered(event)
            return
        }
        context.fireUserInboundEventTriggered(event)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard isSFTP else { return }
        let sshData = unwrapInboundIn(data)
        guard sshData.type == .channel, case var .byteBuffer(buffer) = sshData.data else { return }
        inboundBuffer.writeBuffer(&buffer)

        while let request = try? SFTPPacketCodec.decodeNext(from: &inboundBuffer) {
            let response = virtualFS.handle(request)
            let encoded = SFTPPacketCodec.encode(response, allocator: context.channel.allocator)
            context.writeAndFlush(NIOAny(SSHChannelData(type: .channel, data: .byteBuffer(encoded))), promise: nil)
        }
        inboundBuffer.discardReadBytes()
    }
}

private final class LoopbackDirectTCPIPEchoHandler: ChannelInboundHandler {
    typealias InboundIn = SSHChannelData

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        context.writeAndFlush(data, promise: nil)
    }
}

private final class LoopbackGlobalRequestDelegate:
    GlobalRequestDelegate,
    @unchecked Sendable { // JUSTIFICATION: Synchronizes mock remote forward bound-port allocation in test harness.
    private let lock = NSLock()
    private var nextEphemeralPort = 42100

    func tcpForwardingRequest(
        _ request: GlobalRequest.TCPForwardingRequest,
        handler _: NIOSSHHandler,
        promise: EventLoopPromise<GlobalRequest.TCPForwardingResponse>
    ) {
        switch request {
        case let .listen(_, port):
            lock.lock()
            let bound = port == 0 ? nextEphemeralPort : port
            nextEphemeralPort += 1
            lock.unlock()
            promise.succeed(GlobalRequest.TCPForwardingResponse(boundPort: bound))
        case .cancel:
            promise.succeed(GlobalRequest.TCPForwardingResponse(boundPort: nil))
        }
    }
}
