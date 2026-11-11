import Foundation
import NIOCore
import SparkleCore

/// Pre-SSH SwiftNIO handler negotiating SOCKS5 (RFC 1928) or HTTP CONNECT proxy tunnels
/// before handing the connected byte stream off to `NIOSSHHandler`.
final class SSHProxyChannelHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    typealias InboundOut = ByteBuffer
    typealias OutboundOut = ByteBuffer

    private enum State {
        case awaitingGreeting
        case socks5AwaitingMethod
        case socks5AwaitingConnectReply
        case httpAwaitingConnectReply
        case established
    }

    private let proxy: ProxyConfiguration
    private let targetHost: String
    private let targetPort: Int
    private var state: State = .awaitingGreeting
    private var inboundBuffer = ByteBufferAllocator().buffer(capacity: 512)

    init(proxy: ProxyConfiguration, targetHost: String, targetPort: Int) {
        self.proxy = proxy
        self.targetHost = targetHost
        self.targetPort = targetPort
    }

    func channelActive(context: ChannelHandlerContext) {
        guard !targetHost.contains(where: { $0.isWhitespace || $0.isNewline || $0 == "\0" }),
              (1 ... 65535).contains(targetPort)
        else {
            context.fireErrorCaught(AppError.invalidConfiguration("Invalid proxy target host or port"))
            context.close(promise: nil)
            return
        }

        switch proxy.kind {
        case .none:
            state = .established
            removeSelfAndActivate(context: context)
        case .socks5:
            state = .socks5AwaitingMethod
            var buf = context.channel.allocator.buffer(capacity: 3)
            buf.writeBytes([0x05, 0x01, 0x00])
            context.writeAndFlush(wrapOutboundOut(buf), promise: nil)
        case .http:
            state = .httpAwaitingConnectReply
            let authority = "\(targetHost):\(targetPort)"
            let req = "CONNECT \(authority) HTTP/1.1\r\nHost: \(authority)\r\n\r\n"
            var buf = context.channel.allocator.buffer(capacity: req.utf8.count)
            buf.writeString(req)
            context.writeAndFlush(wrapOutboundOut(buf), promise: nil)
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var chunk = unwrapInboundIn(data)
        guard state != .established else {
            context.fireChannelRead(wrapInboundOut(chunk))
            return
        }
        inboundBuffer.writeBuffer(&chunk)

        switch state {
        case .socks5AwaitingMethod:
            handleSOCKS5MethodReply(context: context)
        case .socks5AwaitingConnectReply:
            handleSOCKS5ConnectReply(context: context)
        case .httpAwaitingConnectReply:
            handleHTTPConnectReply(context: context)
        case .awaitingGreeting, .established:
            break
        }
    }

    private func handleSOCKS5MethodReply(context: ChannelHandlerContext) {
        guard inboundBuffer.readableBytes >= 2,
              let bytes = inboundBuffer.readBytes(length: 2)
        else { return }

        guard bytes[0] == 0x05, bytes[1] == 0x00 else {
            failProxy(context: context, reason: "SOCKS5 proxy rejected no-auth negotiation")
            return
        }

        let hostBytes = Array(targetHost.utf8)
        guard hostBytes.count <= 255 else {
            failProxy(context: context, reason: "Target hostname exceeds SOCKS5 255-byte limit")
            return
        }

        state = .socks5AwaitingConnectReply
        var req = context.channel.allocator.buffer(capacity: 7 + hostBytes.count)
        req.writeBytes([0x05, 0x01, 0x00, 0x03, UInt8(hostBytes.count)])
        req.writeBytes(hostBytes)
        req.writeInteger(UInt16(clamping: targetPort))
        context.writeAndFlush(wrapOutboundOut(req), promise: nil)

        if inboundBuffer.readableBytes > 0 {
            handleSOCKS5ConnectReply(context: context)
        }
    }

    private func handleSOCKS5ConnectReply(context: ChannelHandlerContext) {
        guard inboundBuffer.readableBytes >= 4 else { return }
        let startIdx = inboundBuffer.readerIndex
        guard let header = inboundBuffer.getBytes(at: startIdx, length: 4) else { return }
        guard header[0] == 0x05 else {
            failProxy(context: context, reason: "Invalid SOCKS5 protocol reply version")
            return
        }
        guard header[1] == 0x00 else {
            failProxy(context: context, reason: "SOCKS5 CONNECT failed with code \(header[1])")
            return
        }

        let requiredLength: Int
        switch header[3] {
        case 0x01:
            requiredLength = 10
        case 0x04:
            requiredLength = 22
        case 0x03:
            guard inboundBuffer.readableBytes >= 5,
                  let domainLen = inboundBuffer.getInteger(at: startIdx + 4, as: UInt8.self)
            else { return }
            requiredLength = 7 + Int(domainLen)
        default:
            failProxy(context: context, reason: "Unsupported SOCKS5 address type \(header[3])")
            return
        }

        guard inboundBuffer.readableBytes >= requiredLength else { return }
        inboundBuffer.moveReaderIndex(forwardBy: requiredLength)
        state = .established
        removeSelfAndActivate(context: context)
    }

    private func handleHTTPConnectReply(context: ChannelHandlerContext) {
        let separator = Data("\r\n\r\n".utf8)
        let bytes = inboundBuffer.readableBytesView
        let data = Data(bytes)
        guard let range = data.range(of: separator) else {
            if data.count > 16384 {
                failProxy(context: context, reason: "HTTP CONNECT proxy response headers exceeded 16KB")
            }
            return
        }

        let headerData = data[..<range.lowerBound]
        let headerString = String(data: headerData, encoding: .utf8) ?? ""
        let firstLine = headerString.components(separatedBy: "\r\n").first ?? ""
        let statusParts = firstLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard statusParts.count >= 2,
              statusParts[0].uppercased().hasPrefix("HTTP/"),
              statusParts[1] == "200"
        else {
            failProxy(context: context, reason: "HTTP CONNECT proxy returned: \(firstLine)")
            return
        }

        inboundBuffer.moveReaderIndex(forwardBy: range.upperBound)
        state = .established
        removeSelfAndActivate(context: context)
    }

    private func removeSelfAndActivate(context: ChannelHandlerContext) {
        let readable = inboundBuffer.readableBytes
        let remainder = readable > 0 ? inboundBuffer.readSlice(length: readable) : nil
        context.pipeline.syncOperations.removeHandler(context: context, promise: nil)
        context.fireChannelActive()
        if let remainder {
            context.fireChannelRead(wrapInboundOut(remainder))
        }
    }

    private func failProxy(context: ChannelHandlerContext, reason: String) {
        context.fireErrorCaught(AppError.transferFailed(reason: reason))
        context.close(promise: nil)
    }
}
