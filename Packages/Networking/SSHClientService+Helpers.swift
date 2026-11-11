import Foundation
import NIOCore
import NIOPosix
import NIOSSH
import SparkleCore
import SparkleSecurity

extension SSHClientService {
    func makeBootstrap(
        group: MultiThreadedEventLoopGroup,
        password: String?,
        privateKey: NIOSSHPrivateKey?,
        handshakeBox: SSHHandshakeStateBox,
        includeProxyHandler: Bool = false
    ) -> ClientBootstrap {
        let authDelegate = SparkleSSHUserAuthDelegate(
            username: profile.username,
            authMethod: profile.authMethod,
            password: password,
            privateKey: privateKey
        )
        let hostDelegate = SparkleSSHServerAuthDelegate(
            host: profile.host,
            port: profile.port,
            trustStore: hostTrustStore,
            handshakeBox: handshakeBox,
            promptHandler: hostTrustPrompt
        )
        let forwardMap = remoteForwardMap
        let proxyConfig = profile.proxy
        let targetHost = profile.host
        let targetPort = profile.port

        return ClientBootstrap(group: group)
            .channelInitializer { [authMethod = profile.authMethod] channel in
                channel.eventLoop.makeCompletedFuture {
                    let sync = channel.pipeline.syncOperations
                    if includeProxyHandler {
                        try sync.addHandler(
                            SSHProxyChannelHandler(proxy: proxyConfig, targetHost: targetHost, targetPort: targetPort)
                        )
                    }
                    let config = SSHClientConfiguration(
                        userAuthDelegate: authDelegate,
                        serverAuthDelegate: hostDelegate
                    )
                    let sshHandler = NIOSSHHandler(
                        role: .client(config),
                        allocator: channel.allocator,
                        inboundChildChannelInitializer: { childChannel, channelType in
                            Self.handleInboundChildChannel(
                                childChannel,
                                channelType: channelType,
                                remoteForwardMap: forwardMap,
                                group: group
                            )
                        }
                    )
                    try sync.addHandler(sshHandler)
                    try sync.addHandler(SSHErrorTrackerHandler(authMethod: authMethod, handshakeBox: handshakeBox))
                }
            }
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(IPPROTO_TCP), TCP_NODELAY), value: 1)
            .connectTimeout(.seconds(Int64(stallTimeoutSeconds)))
    }

    func resolvePrivateKey() async throws -> NIOSSHPrivateKey? {
        if let pem = try await loadOptionalSecret(
            ref: profile.privateKeyRef,
            prompt: "Unlock SSH private key for \(profile.name)"
        ), !pem.isEmpty {
            return try PrivateKeyParser.parsePrivateKey(pemString: pem)
        }
        guard let bookmarkData = profile.privateKeyBookmarkData else { return nil }
        let fileURL = try SecurityScopedBookmarkManager.resolveBookmark(bookmarkData)
        let pemFromBookmark = try SecurityScopedBookmarkManager.withScopedAccess(to: fileURL) { scopedURL in
            try String(contentsOf: scopedURL, encoding: .utf8)
        }
        guard !pemFromBookmark.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return try PrivateKeyParser.parsePrivateKey(pemString: pemFromBookmark)
    }

    func loadOptionalSecret(ref: SecretReference?, prompt: String) async throws -> String? {
        guard let ref else { return nil }
        let data = try await credentialStore.loadSecret(for: ref, prompt: profile.requireTouchID ? prompt : nil)
        return String(data: data, encoding: .utf8)
    }

    static func runExec(on rootChannel: Channel, command: String) async throws -> SSHCommandOutput {
        try await withCheckedThrowingContinuation { continuation in
            let eventLoop = rootChannel.eventLoop
            let channelPromise = eventLoop.makePromise(of: Channel.self)
            let stateBox = ExecContinuationBox(continuation: continuation)

            eventLoop.execute {
                do {
                    let sshHandler = try rootChannel.pipeline.syncOperations.handler(type: NIOSSHHandler.self)
                    sshHandler.createChannel(channelPromise, channelType: .session) { childChannel, channelType in
                        guard channelType == .session else {
                            return childChannel.eventLoop.makeFailedFuture(
                                AppError.protocolError(code: -1, message: "Invalid channel type")
                            )
                        }
                        return childChannel.eventLoop.makeCompletedFuture {
                            let handler = BufferedExecChannelHandler(command: command, stateBox: stateBox)
                            try childChannel.pipeline.syncOperations.addHandler(handler)
                        }
                    }
                    channelPromise.futureResult.whenFailure { error in
                        stateBox.fail(error)
                    }
                } catch {
                    stateBox.fail(error)
                }
            }
        }
    }

    static func createSFTPBridge(on rootChannel: Channel, timeoutSeconds: Int = 30) async throws -> SFTPChannelBridge {
        let eventLoop = rootChannel.eventLoop
        let bridge = SFTPChannelBridge(eventLoop: eventLoop, requestTimeoutSeconds: timeoutSeconds)
        let promise = eventLoop.makePromise(of: Channel.self)

        eventLoop.execute {
            do {
                let sshHandler = try rootChannel.pipeline.syncOperations.handler(type: NIOSSHHandler.self)
                sshHandler.createChannel(promise, channelType: .session) { childChannel, channelType in
                    guard channelType == .session else {
                        return childChannel.eventLoop.makeFailedFuture(
                            AppError.protocolError(code: -1, message: "Invalid SSH channel type")
                        )
                    }
                    return childChannel.eventLoop.makeCompletedFuture {
                        let handler = SFTPSubsystemChannelHandler(bridge: bridge)
                        try childChannel.pipeline.syncOperations.addHandler(handler)
                    }
                }
            } catch {
                promise.fail(error)
            }
        }

        let childChannel = try await promise.futureResult.get()
        bridge.attach(channel: childChannel)
        return bridge
    }

    static func mapSSHError(
        _ error: Error,
        host: String,
        port: Int,
        authMethod: AuthMethod
    ) -> AppError {
        if let appError = error as? AppError {
            return appError
        }
        if let sshError = error as? NIOSSHError {
            return AppError.protocolError(code: -1, message: String(describing: sshError))
        }
        let desc = error.localizedDescription
        if desc.lowercased().contains("timed out") {
            return .connectionTimeout(host: host, seconds: 30)
        }
        return .transferFailed(reason: "SSH (\(host):\(port), \(authMethod.rawValue)): \(desc)")
    }
}
