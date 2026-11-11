import Foundation
import NIOCore
import NIOSSH
import SparkleCore
import SparkleSecurity

final class SSHHandshakeStateBox:
    @unchecked Sendable { // JUSTIFICATION: NSLock serializes single-shot handshake promise and error state.
    private let lock = NSLock()
    private var recordedError: Error?
    private var completed = false
    private let promise: EventLoopPromise<Void>

    init(promise: EventLoopPromise<Void>) {
        self.promise = promise
    }

    var futureResult: EventLoopFuture<Void> {
        promise.futureResult
    }

    func recordFailure(_ error: Error) {
        lock.lock()
        if recordedError == nil {
            recordedError = error
        }
        lock.unlock()
    }

    func succeedHandshake() {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return
        }
        completed = true
        lock.unlock()
        promise.succeed(())
    }

    func failHandshake(defaultError: Error) {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return
        }
        completed = true
        let resolved = recordedError ?? defaultError
        lock.unlock()
        promise.fail(resolved)
    }
}

final class SparkleSSHServerAuthDelegate:
    NIOSSHClientServerAuthenticationDelegate,
    @unchecked Sendable { // JUSTIFICATION: Immutable references to Sendable actors/closures.
    private let host: String
    private let port: Int
    private let trustStore: any HostTrustStoreProtocol
    private let promptHandler: SSHClientService.HostTrustPromptHandler
    private let handshakeBox: SSHHandshakeStateBox

    init(
        host: String,
        port: Int,
        trustStore: any HostTrustStoreProtocol,
        handshakeBox: SSHHandshakeStateBox,
        promptHandler: @escaping SSHClientService.HostTrustPromptHandler
    ) {
        self.host = host
        self.port = port
        self.trustStore = trustStore
        self.handshakeBox = handshakeBox
        self.promptHandler = promptHandler
    }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        let fingerprint = SSHKeyFingerprint.sha256(for: hostKey)
        let algorithm = SSHKeyFingerprint.keyAlgorithm(for: hostKey)

        Task { [host, port, trustStore, handshakeBox, promptHandler] in
            let state = await trustStore.evaluate(host: host, port: port, fingerprint: fingerprint)
            switch state {
            case .trusted:
                validationCompletePromise.succeed(())
            case let .mismatch(expected, got):
                let err = AppError.hostKeyMismatch(host: host, expected: expected, got: got)
                handshakeBox.recordFailure(err)
                validationCompletePromise.fail(err)
            case .rejected:
                let err = AppError.hostKeyRejected(host: host, port: port)
                handshakeBox.recordFailure(err)
                validationCompletePromise.fail(err)
            case .corrupted:
                let err = AppError.hostTrustCorrupted(host: host)
                handshakeBox.recordFailure(err)
                validationCompletePromise.fail(err)
            case .unknown, .pendingUserDecision:
                let challenge = HostKeyChallenge(
                    host: host,
                    port: port,
                    algorithm: algorithm,
                    fingerprintSHA256: fingerprint
                )
                let accepted = await promptHandler(challenge)
                if accepted {
                    do {
                        try await trustStore.trust(host: host, port: port, fingerprint: fingerprint)
                        validationCompletePromise.succeed(())
                    } catch {
                        handshakeBox.recordFailure(error)
                        validationCompletePromise.fail(error)
                    }
                } else {
                    try? await trustStore.reject(host: host, port: port)
                    let err = AppError.hostKeyRejected(host: host, port: port)
                    handshakeBox.recordFailure(err)
                    validationCompletePromise.fail(err)
                }
            }
        }
    }
}

final class SparkleSSHUserAuthDelegate:
    NIOSSHClientUserAuthenticationDelegate,
    @unchecked Sendable { // JUSTIFICATION: NSLock guards single-shot auth attempt flag.
    private let lock = NSLock()
    private let username: String
    private let authMethod: AuthMethod
    private let password: String?
    private let privateKey: NIOSSHPrivateKey?
    private var attempted = false

    init(
        username: String,
        authMethod: AuthMethod,
        password: String?,
        privateKey: NIOSSHPrivateKey?
    ) {
        self.username = username
        self.authMethod = authMethod
        self.password = password
        self.privateKey = privateKey
    }

    func nextAuthenticationType(
        availableMethods: NIOSSHAvailableUserAuthenticationMethods,
        nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>
    ) {
        lock.lock()
        let alreadyAttempted = attempted
        attempted = true
        lock.unlock()

        if alreadyAttempted {
            nextChallengePromise.fail(AppError.authenticationFailed(method: authMethod))
            return
        }

        switch authMethod {
        case .publicKey, .sshAgent:
            if availableMethods.contains(.publicKey), let privateKey {
                let offer = NIOSSHUserAuthenticationOffer(
                    username: username,
                    serviceName: "",
                    offer: .privateKey(.init(privateKey: privateKey))
                )
                nextChallengePromise.succeed(offer)
                return
            }
            if availableMethods.contains(.password), let password {
                let offer = NIOSSHUserAuthenticationOffer(
                    username: username,
                    serviceName: "",
                    offer: .password(.init(password: password))
                )
                nextChallengePromise.succeed(offer)
                return
            }
            nextChallengePromise.fail(AppError.authenticationFailed(method: authMethod))

        case .password, .keyboardInteractive, .anonymous:
            if availableMethods.contains(.password), let password {
                let offer = NIOSSHUserAuthenticationOffer(
                    username: username,
                    serviceName: "",
                    offer: .password(.init(password: password))
                )
                nextChallengePromise.succeed(offer)
            } else {
                nextChallengePromise.fail(AppError.authenticationFailed(method: authMethod))
            }
        }
    }
}

final class SSHErrorTrackerHandler: ChannelInboundHandler {
    typealias InboundIn = Any

    private let authMethod: AuthMethod
    private let handshakeBox: SSHHandshakeStateBox

    init(authMethod: AuthMethod, handshakeBox: SSHHandshakeStateBox) {
        self.authMethod = authMethod
        self.handshakeBox = handshakeBox
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if event is UserAuthSuccessEvent {
            handshakeBox.succeedHandshake()
        }
        context.fireUserInboundEventTriggered(event)
    }

    func channelInactive(context: ChannelHandlerContext) {
        handshakeBox.failHandshake(defaultError: AppError.authenticationFailed(method: authMethod))
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        DiagnosticsLogger.network.error("SSH pipeline error: \(error.localizedDescription, privacy: .public)")
        handshakeBox.failHandshake(defaultError: error)
        context.close(promise: nil)
    }
}

final class ExecContinuationBox: @unchecked Sendable { // JUSTIFICATION: NSLock guards single-shot completion.
    private let lock = NSLock()
    private var continuation: CheckedContinuation<SSHCommandOutput, Error>?

    init(continuation: CheckedContinuation<SSHCommandOutput, Error>) {
        self.continuation = continuation
    }

    func succeed(_ output: SSHCommandOutput) {
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.resume(returning: output)
    }

    func fail(_ error: Error) {
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.resume(throwing: error)
    }
}

final class BufferedExecChannelHandler: ChannelInboundHandler {
    typealias InboundIn = SSHChannelData

    private let command: String
    private let stateBox: ExecContinuationBox
    private var stdoutBuffer = Data()
    private var stderrBuffer = Data()
    private var exitCode = 0

    init(command: String, stateBox: ExecContinuationBox) {
        self.command = command
        self.stateBox = stateBox
    }

    func channelActive(context: ChannelHandlerContext) {
        let request = SSHChannelRequestEvent.ExecRequest(command: command, wantReply: true)
        context.triggerUserOutboundEvent(request, promise: nil)
    }

    func channelRead(context _: ChannelHandlerContext, data: NIOAny) {
        let channelData = unwrapInboundIn(data)
        guard case var .byteBuffer(buffer) = channelData.data,
              let bytes = buffer.readBytes(length: buffer.readableBytes)
        else { return }
        switch channelData.type {
        case .channel:
            stdoutBuffer.append(contentsOf: bytes)
        case .stdErr:
            stderrBuffer.append(contentsOf: bytes)
        default:
            break
        }
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if let exit = event as? SSHChannelRequestEvent.ExitStatus {
            exitCode = exit.exitStatus
        } else {
            context.fireUserInboundEventTriggered(event)
        }
    }

    func channelInactive(context _: ChannelHandlerContext) {
        let stdout = String(data: stdoutBuffer, encoding: .utf8) ?? ""
        let stderr = String(data: stderrBuffer, encoding: .utf8) ?? ""
        stateBox.succeed(SSHCommandOutput(exitCode: exitCode, stdout: stdout, stderr: stderr))
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        stateBox.fail(error)
        context.close(promise: nil)
    }
}

final class SSHPTYChannelHandler: ChannelInboundHandler {
    typealias InboundIn = SSHChannelData

    private let term: String
    private let cols: Int
    private let rows: Int
    private let continuation: AsyncStream<[UInt8]>.Continuation

    init(term: String, cols: Int, rows: Int, continuation: AsyncStream<[UInt8]>.Continuation) {
        self.term = term
        self.cols = cols
        self.rows = rows
        self.continuation = continuation
    }

    func channelActive(context: ChannelHandlerContext) {
        let pty = SSHChannelRequestEvent.PseudoTerminalRequest(
            wantReply: true,
            term: term,
            terminalCharacterWidth: cols,
            terminalRowHeight: rows,
            terminalPixelWidth: 0,
            terminalPixelHeight: 0,
            terminalModes: SSHTerminalModes([:])
        )
        context.triggerUserOutboundEvent(pty, promise: nil)
        context.triggerUserOutboundEvent(SSHChannelRequestEvent.ShellRequest(wantReply: true), promise: nil)
    }

    func channelRead(context _: ChannelHandlerContext, data: NIOAny) {
        let channelData = unwrapInboundIn(data)
        guard case var .byteBuffer(buffer) = channelData.data,
              let bytes = buffer.readBytes(length: buffer.readableBytes)
        else { return }
        continuation.yield(bytes)
    }

    func channelInactive(context _: ChannelHandlerContext) {
        continuation.finish()
    }

    func errorCaught(context: ChannelHandlerContext, error _: Error) {
        continuation.finish()
        context.close(promise: nil)
    }
}
