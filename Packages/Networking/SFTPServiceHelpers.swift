import Foundation
import SparkleCore

struct SFTPDownloadChunkContext: Sendable {
    let bridge: SFTPChannelBridge
    let handle: Data
    let remotePath: RemotePath
    let localURL: URL
    let initialOffset: Int64
    let totalBytes: Int64
    let onProgress: @Sendable (TransferProgress) -> Void
}

struct SFTPUploadChunkContext: Sendable {
    let bridge: SFTPChannelBridge
    let handle: Data
    let remotePath: RemotePath
    let localURL: URL
    let initialOffset: Int64
    let totalBytes: Int64
    let onProgress: @Sendable (TransferProgress) -> Void
}

extension SFTPService {
    func transferDownloadChunks(_ ctx: SFTPDownloadChunkContext) async throws {
        let fileHandle = try prepareWritableFile(at: ctx.localURL, offset: ctx.initialOffset)
        defer { try? fileHandle.close() }

        var currentOffset = UInt64(max(0, ctx.initialOffset))
        let startTime = ContinuousClock.now

        while true {
            try Task.checkCancellation()
            let readResp = try await ctx.bridge.send(
                .read(
                    requestID: ctx.bridge.allocateRequestID(),
                    handle: ctx.handle,
                    offset: currentOffset,
                    length: UInt32(chunkSize)
                )
            )
            switch readResp {
            case .data(_, let chunk) where !chunk.isEmpty:
                try fileHandle.write(contentsOf: chunk)
                currentOffset += UInt64(chunk.count)
                emitProgress(ctx: ctx, currentOffset: currentOffset, startTime: startTime)
            case .data, .status(_, .eof, _, _):
                emitProgress(ctx: ctx, currentOffset: currentOffset, startTime: startTime)
                return
            case .status(_, let code, let msg, _):
                throw Self.mapStatusError(code: code, message: msg, path: ctx.remotePath.rawValue)
            default:
                throw AppError.protocolError(code: -1, message: "Unexpected SFTP READ response")
            }
        }
    }

    private func prepareWritableFile(at url: URL, offset: Int64) throws -> FileHandle {
        if offset == 0 || !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let handle = try FileHandle(forUpdating: url)
        try handle.seek(toOffset: UInt64(max(0, offset)))
        return handle
    }

    private func emitProgress(
        ctx: SFTPDownloadChunkContext,
        currentOffset: UInt64,
        startTime: ContinuousClock.Instant
    ) {
        let speed = Self.calculateSpeed(bytes: Int64(currentOffset) - ctx.initialOffset, since: startTime)
        ctx.onProgress(
            TransferProgress(bytesTransferred: Int64(currentOffset), totalBytes: ctx.totalBytes, bytesPerSecond: speed)
        )
    }

    func transferUploadChunks(_ ctx: SFTPUploadChunkContext) async throws {
        let fileHandle = try FileHandle(forReadingFrom: ctx.localURL)
        defer { try? fileHandle.close() }
        try fileHandle.seek(toOffset: UInt64(max(0, ctx.initialOffset)))

        var currentOffset = UInt64(max(0, ctx.initialOffset))
        let startTime = ContinuousClock.now

        while true {
            try Task.checkCancellation()
            let chunk = try fileHandle.read(upToCount: chunkSize) ?? Data()
            if chunk.isEmpty {
                let speed = Self.calculateSpeed(bytes: Int64(currentOffset) - ctx.initialOffset, since: startTime)
                ctx.onProgress(
                    TransferProgress(
                        bytesTransferred: Int64(currentOffset),
                        totalBytes: ctx.totalBytes,
                        bytesPerSecond: speed
                    )
                )
                return
            }
            let writeResp = try await ctx.bridge.send(
                .write(
                    requestID: ctx.bridge.allocateRequestID(),
                    handle: ctx.handle,
                    offset: currentOffset,
                    data: chunk
                )
            )
            try verifyStatusOK(writeResp, path: ctx.remotePath.rawValue)
            currentOffset += UInt64(chunk.count)
            let speed = Self.calculateSpeed(bytes: Int64(currentOffset) - ctx.initialOffset, since: startTime)
            ctx.onProgress(
                TransferProgress(
                    bytesTransferred: Int64(currentOffset),
                    totalBytes: ctx.totalBytes,
                    bytesPerSecond: speed
                )
            )
        }
    }

    func requireBridge() throws -> SFTPChannelBridge {
        guard let bridge else { throw AppError.notConnected }
        return bridge
    }

    func extractHandle(from packet: SFTPPacket, path: String) throws -> Data {
        switch packet {
        case .handle(_, let handle):
            return handle
        case .status(_, let code, let message, _):
            throw Self.mapStatusError(code: code, message: message, path: path)
        default:
            throw AppError.protocolError(code: -1, message: "Expected SFTP handle")
        }
    }

    func extractAttrs(from packet: SFTPPacket, path: String) throws -> SFTPAttributes {
        switch packet {
        case .attrs(_, let attrs):
            return attrs
        case .status(_, let code, let message, _):
            throw Self.mapStatusError(code: code, message: message, path: path)
        default:
            throw AppError.protocolError(code: -1, message: "Expected SFTP attributes")
        }
    }

    func verifyStatusOK(_ packet: SFTPPacket, path: String) throws {
        guard case .status(_, let code, let message, _) = packet else {
            throw AppError.protocolError(code: -1, message: "Expected SFTP status")
        }
        guard code == .succeeded else {
            throw Self.mapStatusError(code: code, message: message, path: path)
        }
    }

    static func mapStatusError(code: SFTPStatusCode, message: String, path: String) -> AppError {
        switch code {
        case .noSuchFile:
            return .fileNotFound(path: path)
        case .permissionDenied:
            return .permissionDenied(path: path)
        default:
            return .protocolError(code: Int(code.rawValue), message: message)
        }
    }

    static func calculateSpeed(bytes: Int64, since start: ContinuousClock.Instant) -> Int64 {
        let elapsed = ContinuousClock.now - start
        let seconds = Double(elapsed.components.seconds) + (Double(elapsed.components.attoseconds) / 1e18)
        guard seconds > 0.05 else { return max(0, bytes) }
        return max(0, Int64(Double(bytes) / seconds))
    }
}
