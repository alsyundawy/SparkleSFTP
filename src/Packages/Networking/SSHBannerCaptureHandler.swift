import Foundation
import NIOCore
import SparkleCore

final class SSHBannerCaptureHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    typealias InboundOut = ByteBuffer

    private let handshakeBox: SSHHandshakeStateBox

    init(handshakeBox: SSHHandshakeStateBox) {
        self.handshakeBox = handshakeBox
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        if handshakeBox.serverBanner == nil {
            var temp = unwrapInboundIn(data)
            if let string = temp.readString(length: min(temp.readableBytes, 512)) {
                let lines = string.components(separatedBy: .newlines)
                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.hasPrefix("SSH-") {
                        handshakeBox.recordBanner(trimmed)
                        break
                    }
                }
            }
        }
        context.fireChannelRead(data)
    }
}
