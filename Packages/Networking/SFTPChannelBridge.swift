import Foundation
import NIOCore
import NIOSSH
import SparkleCore

/// Bridges an active SFTP subsystem channel to async/await packet sends & receives.
public final class SFTPChannelBridge:
    @unchecked Sendable { // JUSTIFICATION: NSLock guards request continuations & buffer; I/O runs on eventLoop.
    private let lock = NSLock()
    private let eventLoop: EventLoop
    private let requestTimeoutSeconds: Int
    private var channel: Channel?
    private var nextRequestID: UInt32 = 1
    private var inboundBuffer = ByteBufferAllocator().buffer(capacity: 4096)
    private var versionContinuation: CheckedContinuation<UInt32, Error>?
    private var pendingRequests: [UInt32: CheckedContinuation<SFTPPacket, Error>] = [:]
    private var isClosed = false

    init(eventLoop: EventLoop, requestTimeoutSeconds: Int = 30) {
        self.eventLoop = eventLoop
        self.requestTimeoutSeconds = max(1, requestTimeoutSeconds)
    }

    func attach(channel: Channel) {
        lock.lock()
        self.channel = channel
        lock.unlock()
    }

    public func allocateRequestID() -> UInt32 {
        lock.lock()
        defer { lock.unlock() }
        let current = nextRequestID
        nextRequestID = nextRequestID &+ 1
        if nextRequestID == 0 {
            nextRequestID = 1
        }
        return current
    }

    public func initializeSFTP() async throws -> UInt32 {
        let packet = SFTPPacket.initialize(version: 3)
        let bytes = SFTPPacketCodec.encode(packet)
        let timeout = requestTimeoutSeconds

        return try await withThrowingTaskGroup(of: UInt32.self) { group in
            group.addTask {
                try await withTaskCancellationHandler {
                    try await withCheckedThrowingContinuation { continuation in
                        self.lock.lock()
                        if self.isClosed {
                            self.lock.unlock()
                            continuation.resume(throwing: AppError.notConnected)
                            return
                        }
                        self.versionContinuation = continuation
                        let activeChannel = self.channel
                        self.lock.unlock()

                        guard let activeChannel else {
                            self.failAll(AppError.notConnected)
                            return
                        }
                        activeChannel.eventLoop.execute {
                            let data = SSHChannelData(type: .channel, data: .byteBuffer(bytes))
                            activeChannel.writeAndFlush(data, promise: nil)
                        }
                    }
                } onCancel: {
                    self.failVersion(error: CancellationError())
                }
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw AppError.channelStalled(reason: "SFTP initialization timed out after \(timeout)s")
            }
            guard let version = try await group.next() else {
                throw AppError.channelStalled(reason: "SFTP initialization aborted")
            }
            group.cancelAll()
            return version
        }
    }

    public func send(_ packet: SFTPPacket) async throws -> SFTPPacket {
        guard let requestID = packet.requestID else {
            throw AppError.protocolError(code: -1, message: "Missing SFTP request ID")
        }
        let encoded = SFTPPacketCodec.encode(packet)
        let timeout = requestTimeoutSeconds

        return try await withThrowingTaskGroup(of: SFTPPacket.self) { group in
            group.addTask {
                try await withTaskCancellationHandler {
                    try await withCheckedThrowingContinuation { continuation in
                        self.lock.lock()
                        if self.isClosed {
                            self.lock.unlock()
                            continuation.resume(throwing: AppError.notConnected)
                            return
                        }
                        self.pendingRequests[requestID] = continuation
                        let activeChannel = self.channel
                        self.lock.unlock()

                        guard let activeChannel else {
                            self.failPending(id: requestID, error: AppError.notConnected)
                            return
                        }
                        activeChannel.eventLoop.execute {
                            let data = SSHChannelData(type: .channel, data: .byteBuffer(encoded))
                            activeChannel.writeAndFlush(data, promise: nil)
                        }
                    }
                } onCancel: {
                    self.failPending(id: requestID, error: CancellationError())
                }
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw AppError.channelStalled(reason: "SFTP request timed out after \(timeout)s")
            }
            guard let response = try await group.next() else {
                throw AppError.channelStalled(reason: "SFTP request aborted")
            }
            group.cancelAll()
            return response
        }
    }

    public func close() {
        failAll(AppError.notConnected)
        lock.lock()
        let activeChannel = channel
        channel = nil
        lock.unlock()
        activeChannel?.close(promise: nil)
    }

    func receive(buffer: inout ByteBuffer) {
        lock.lock()
        inboundBuffer.writeBuffer(&buffer)
        var decodedPackets: [SFTPPacket] = []
        var decodeError: Error?
        do {
            while let packet = try SFTPPacketCodec.decodeNext(from: &inboundBuffer) {
                decodedPackets.append(packet)
            }
            inboundBuffer.discardReadBytes()
        } catch {
            decodeError = error
        }
        lock.unlock()

        if let decodeError {
            failAll(decodeError)
            return
        }

        for packet in decodedPackets {
            dispatchDecoded(packet)
        }
    }

    func failAll(_ error: Error) {
        lock.lock()
        isClosed = true
        let vCont = versionContinuation
        versionContinuation = nil
        let requests = pendingRequests
        pendingRequests.removeAll()
        lock.unlock()

        vCont?.resume(throwing: error)
        for (_, cont) in requests {
            cont.resume(throwing: error)
        }
    }

    private func failVersion(error: Error) {
        lock.lock()
        let cont = versionContinuation
        versionContinuation = nil
        lock.unlock()
        cont?.resume(throwing: error)
    }

    private func failPending(id: UInt32, error: Error) {
        lock.lock()
        let cont = pendingRequests.removeValue(forKey: id)
        lock.unlock()
        cont?.resume(throwing: error)
    }

    private func dispatchDecoded(_ packet: SFTPPacket) {
        if case let .version(version, _) = packet {
            lock.lock()
            let cont = versionContinuation
            versionContinuation = nil
            lock.unlock()
            cont?.resume(returning: version)
            return
        }
        guard let reqID = packet.requestID else { return }
        lock.lock()
        let cont = pendingRequests.removeValue(forKey: reqID)
        lock.unlock()
        cont?.resume(returning: packet)
    }
}

final class SFTPSubsystemChannelHandler: ChannelInboundHandler {
    typealias InboundIn = SSHChannelData

    private let bridge: SFTPChannelBridge

    init(bridge: SFTPChannelBridge) {
        self.bridge = bridge
    }

    func channelActive(context: ChannelHandlerContext) {
        let req = SSHChannelRequestEvent.SubsystemRequest(subsystem: "sftp", wantReply: true)
        context.triggerUserOutboundEvent(req, promise: nil)
    }

    func channelRead(context _: ChannelHandlerContext, data: NIOAny) {
        let channelData = unwrapInboundIn(data)
        guard channelData.type == .channel, case var .byteBuffer(buffer) = channelData.data else {
            return
        }
        bridge.receive(buffer: &buffer)
    }

    func channelInactive(context _: ChannelHandlerContext) {
        bridge.failAll(AppError.notConnected)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        bridge.failAll(error)
        context.close(promise: nil)
    }
}
