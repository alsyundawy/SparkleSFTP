import Foundation
import NIOCore
import NIOSSH

/// Bridges `SSHChannelData` (`DirectTCPIP` / `forwardedTCPIP`) payloads with raw `ByteBuffer` TCP sockets.
public final class SSHChannelByteWrapper: ChannelDuplexHandler {
    public typealias InboundIn = SSHChannelData
    public typealias InboundOut = ByteBuffer
    public typealias OutboundIn = ByteBuffer
    public typealias OutboundOut = SSHChannelData

    public init() {}

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let sshData = unwrapInboundIn(data)
        if case let .byteBuffer(buffer) = sshData.data {
            context.fireChannelRead(wrapInboundOut(buffer))
        }
    }

    public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let buffer = unwrapOutboundIn(data)
        context.write(wrapOutboundOut(SSHChannelData(type: .channel, data: .byteBuffer(buffer))), promise: promise)
    }
}

/// Forwards raw `ByteBuffer` frames between paired NIO channels, buffering pre-activation reads safely.
public final class TunnelGlueHandler:
    ChannelInboundHandler,
    @unchecked Sendable { // JUSTIFICATION: NSLock serializes pre-activation buffering until peer channel becomes ready.
    public typealias InboundIn = ByteBuffer

    private static let maxBufferedBytes = 4 * 1024 * 1024

    private enum ReadAction {
        case forward
        case buffered
        case overflow
    }

    private let peerChannel: Channel
    private let onChannelActive: (@Sendable () -> Void)?
    private let lock = NSLock()
    private var didFireActive = false
    private var peerReady: Bool
    private var pendingFrames: [ByteBuffer] = []
    private var pendingBytes = 0
    private var pendingClose = false

    public init(
        peerChannel: Channel,
        waitForPeerActivation: Bool = false,
        onChannelActive: (@Sendable () -> Void)? = nil
    ) {
        self.peerChannel = peerChannel
        self.onChannelActive = onChannelActive
        peerReady = !waitForPeerActivation
    }

    public func handlerAdded(context: ChannelHandlerContext) {
        if context.channel.isActive {
            fireActiveOnce()
        }
    }

    public func channelActive(context: ChannelHandlerContext) {
        fireActiveOnce()
        context.fireChannelActive()
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buffer = unwrapInboundIn(data)
        let action = enqueueOrCheckForward(buffer)
        switch action {
        case .forward:
            if peerChannel.isActive {
                peerChannel.writeAndFlush(buffer, promise: nil)
            }
        case .buffered:
            break
        case .overflow:
            context.close(promise: nil)
        }
    }

    public func markPeerReady() {
        guard peerChannel.eventLoop.inEventLoop else {
            peerChannel.eventLoop.execute { self.markPeerReady() }
            return
        }
        let drained = drainPendingState()
        guard peerChannel.isActive else { return }
        for frame in drained.frames {
            peerChannel.write(frame, promise: nil)
        }
        if !drained.frames.isEmpty {
            peerChannel.flush()
        }
        if drained.shouldClose {
            peerChannel.close(promise: nil)
        }
    }

    public func channelInactive(context _: ChannelHandlerContext) {
        if shouldClosePeerOnTeardown(), peerChannel.isActive {
            peerChannel.close(promise: nil)
        }
    }

    public func errorCaught(context: ChannelHandlerContext, error _: Error) {
        context.close(promise: nil)
        if shouldClosePeerOnTeardown(), peerChannel.isActive {
            peerChannel.close(promise: nil)
        }
    }

    private func enqueueOrCheckForward(_ buffer: ByteBuffer) -> ReadAction {
        lock.lock()
        defer { lock.unlock() }
        if peerReady {
            return .forward
        }
        let incomingBytes = buffer.readableBytes
        guard pendingBytes + incomingBytes <= Self.maxBufferedBytes else {
            pendingFrames.removeAll(keepingCapacity: false)
            pendingBytes = 0
            return .overflow
        }
        pendingFrames.append(buffer)
        pendingBytes += incomingBytes
        return .buffered
    }

    private func drainPendingState() -> (frames: [ByteBuffer], shouldClose: Bool) {
        lock.lock()
        defer { lock.unlock() }
        let frames = pendingFrames
        let shouldClose = pendingClose
        pendingFrames.removeAll(keepingCapacity: false)
        pendingBytes = 0
        peerReady = true
        return (frames, shouldClose)
    }

    private func shouldClosePeerOnTeardown() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if !peerReady {
            pendingClose = true
            return false
        }
        return true
    }

    private func fireActiveOnce() {
        lock.lock()
        guard !didFireActive else {
            lock.unlock()
            return
        }
        didFireActive = true
        let callback = onChannelActive
        lock.unlock()
        callback?()
    }
}
