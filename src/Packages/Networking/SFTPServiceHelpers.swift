import Foundation
import SparkleCore

struct SFTPDownloadChunkContext: Sendable {
    let bridge: SFTPChannelBridge
    let handle: Data
    let remotePath: RemotePath
    let localURL: URL
    let initialOffset: Int64
    let totalBytes: Int64
    let inFlightWindow: Int
    let onProgress: @Sendable (TransferProgress) -> Void
}

struct SFTPUploadChunkContext: Sendable {
    let bridge: SFTPChannelBridge
    let handle: Data
    let remotePath: RemotePath
    let localURL: URL
    let initialOffset: Int64
    let totalBytes: Int64
    let inFlightWindow: Int
    let onProgress: @Sendable (TransferProgress) -> Void
}

private struct SFTPReadSliceResult: Sendable {
    let offset: UInt64
    let requestedLength: UInt32
    let data: Data
    let reachedEOF: Bool
}

private struct SFTPDownloadWindowState {
    var nextRequestOffset: UInt64
    var nextWriteOffset: UInt64
    var pendingChunks: [UInt64: Data] = [:]
    var gapSlices: [(offset: UInt64, length: UInt32)] = []
    var eofOffset: UInt64?

    var hasKnownRemaining: Bool {
        if let eofOffset, nextWriteOffset >= eofOffset {
            return false
        }
        return true
    }
}

private final class UploadChunkCursor:
    @unchecked Sendable { // JUSTIFICATION: NSLock serializes FileHandle reads.
    private let lock = NSLock()
    private let fileHandle: FileHandle
    private let chunkSize: Int
    private var nextOffset: UInt64

    init(fileHandle: FileHandle, chunkSize: Int, startOffset: UInt64) {
        self.fileHandle = fileHandle
        self.chunkSize = chunkSize
        nextOffset = startOffset
    }

    func nextSlice() throws -> (offset: UInt64, data: Data)? {
        lock.lock()
        defer { lock.unlock() }
        let chunk = try fileHandle.read(upToCount: chunkSize) ?? Data()
        guard !chunk.isEmpty else { return nil }
        let offset = nextOffset
        nextOffset += UInt64(chunk.count)
        return (offset, chunk)
    }
}

extension SFTPService {
    func transferDownloadChunks(_ ctx: SFTPDownloadChunkContext) async throws {
        try await SFTPPipelinedTransfer.transferDownload(ctx, chunkSize: chunkSize)
    }

    func transferUploadChunks(_ ctx: SFTPUploadChunkContext) async throws {
        try await SFTPPipelinedTransfer.transferUpload(ctx, chunkSize: chunkSize)
    }

    func requireBridge() throws -> SFTPChannelBridge {
        guard let bridge else { throw AppError.notConnected }
        return bridge
    }

    func extractHandle(from packet: SFTPPacket, path: String) throws -> Data {
        switch packet {
        case let .handle(_, handle):
            return handle
        case let .status(_, code, message, _):
            throw Self.mapStatusError(code: code, message: message, path: path)
        default:
            throw AppError.protocolError(code: -1, message: "Expected SFTP handle")
        }
    }

    func extractAttrs(from packet: SFTPPacket, path: String) throws -> SFTPAttributes {
        switch packet {
        case let .attrs(_, attrs):
            return attrs
        case let .status(_, code, message, _):
            throw Self.mapStatusError(code: code, message: message, path: path)
        default:
            throw AppError.protocolError(code: -1, message: "Expected SFTP attributes")
        }
    }

    func verifyStatusOK(_ packet: SFTPPacket, path: String) throws {
        try Self.verifyStatusOKPacket(packet, path: path)
    }

    static func verifyStatusOKPacket(_ packet: SFTPPacket, path: String) throws {
        guard case let .status(_, code, message, _) = packet else {
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

private enum SFTPPipelinedTransfer {
    static func transferDownload(_ ctx: SFTPDownloadChunkContext, chunkSize: Int) async throws {
        let fileHandle = try prepareWritableFile(at: ctx.localURL, offset: ctx.initialOffset)
        defer { try? fileHandle.close() }

        let startOffset = UInt64(max(0, ctx.initialOffset))
        let startTime = ContinuousClock.now
        let windowLimit = ctx.totalBytes > 0 ? max(1, ctx.inFlightWindow) : 1
        var state = SFTPDownloadWindowState(nextRequestOffset: startOffset, nextWriteOffset: startOffset)

        try await withThrowingTaskGroup(of: SFTPReadSliceResult.self) { group in
            var active = 0
            while active < windowLimit, scheduleNextRead(into: &group, ctx: ctx, state: &state, chunkSize: chunkSize) {
                active += 1
            }
            while let result = try await group.next() {
                try Task.checkCancellation()
                active -= 1
                try handleDownloadSlice(result, ctx: ctx, state: &state, fileHandle: fileHandle, startTime: startTime)
                while state.hasKnownRemaining,
                      active < windowLimit,
                      scheduleNextRead(into: &group, ctx: ctx, state: &state, chunkSize: chunkSize) {
                    active += 1
                }
            }
        }
        emitDownloadProgress(ctx: ctx, currentOffset: state.nextWriteOffset, startTime: startTime)
    }

    private static func scheduleNextRead(
        into group: inout ThrowingTaskGroup<SFTPReadSliceResult, Error>,
        ctx: SFTPDownloadChunkContext,
        state: inout SFTPDownloadWindowState,
        chunkSize: Int
    ) -> Bool {
        if !state.gapSlices.isEmpty {
            let gap = state.gapSlices.removeFirst()
            enqueueDownloadRead(into: &group, ctx: ctx, offset: gap.offset, length: gap.length)
            return true
        }
        if let eof = state.eofOffset, state.nextRequestOffset >= eof {
            return false
        }
        if ctx.totalBytes > 0, state.nextRequestOffset >= UInt64(ctx.totalBytes) {
            return false
        }
        let offset = state.nextRequestOffset
        let length = UInt32(chunkSize)
        state.nextRequestOffset += UInt64(length)
        enqueueDownloadRead(into: &group, ctx: ctx, offset: offset, length: length)
        return true
    }

    private static func enqueueDownloadRead(
        into group: inout ThrowingTaskGroup<SFTPReadSliceResult, Error>,
        ctx: SFTPDownloadChunkContext,
        offset: UInt64,
        length: UInt32
    ) {
        group.addTask {
            try Task.checkCancellation()
            let resp = try await ctx.bridge.send(
                .read(requestID: ctx.bridge.allocateRequestID(), handle: ctx.handle, offset: offset, length: length)
            )
            switch resp {
            case let .data(_, chunk) where !chunk.isEmpty:
                return SFTPReadSliceResult(offset: offset, requestedLength: length, data: chunk, reachedEOF: false)
            case .data, .status(_, .eof, _, _):
                return SFTPReadSliceResult(offset: offset, requestedLength: length, data: Data(), reachedEOF: true)
            case let .status(_, code, msg, _):
                throw SFTPService.mapStatusError(code: code, message: msg, path: ctx.remotePath.rawValue)
            default:
                throw AppError.protocolError(code: -1, message: "Unexpected SFTP READ response")
            }
        }
    }

    private static func handleDownloadSlice(
        _ result: SFTPReadSliceResult,
        ctx: SFTPDownloadChunkContext,
        state: inout SFTPDownloadWindowState,
        fileHandle: FileHandle,
        startTime: ContinuousClock.Instant
    ) throws {
        if result.reachedEOF || result.data.isEmpty {
            state.eofOffset = min(state.eofOffset ?? result.offset, result.offset)
        } else {
            state.pendingChunks[result.offset] = result.data
            let received = UInt32(result.data.count)
            if received < result.requestedLength {
                let nextOff = result.offset + UInt64(received)
                let remLen = result.requestedLength - received
                let knownEnd = state.eofOffset ?? (ctx.totalBytes > 0 ? UInt64(ctx.totalBytes) : UInt64.max)
                if nextOff < knownEnd {
                    state.gapSlices.append((offset: nextOff, length: remLen))
                }
            }
        }
        while let contiguous = state.pendingChunks.removeValue(forKey: state.nextWriteOffset) {
            try fileHandle.write(contentsOf: contiguous)
            state.nextWriteOffset += UInt64(contiguous.count)
            emitDownloadProgress(ctx: ctx, currentOffset: state.nextWriteOffset, startTime: startTime)
        }
    }

    private static func prepareWritableFile(at url: URL, offset: Int64) throws -> FileHandle {
        if offset == 0 || !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let handle = try FileHandle(forUpdating: url)
        try handle.seek(toOffset: UInt64(max(0, offset)))
        return handle
    }

    private static func emitDownloadProgress(
        ctx: SFTPDownloadChunkContext,
        currentOffset: UInt64,
        startTime: ContinuousClock.Instant
    ) {
        let speed = SFTPService.calculateSpeed(bytes: Int64(currentOffset) - ctx.initialOffset, since: startTime)
        ctx.onProgress(
            TransferProgress(bytesTransferred: Int64(currentOffset), totalBytes: ctx.totalBytes, bytesPerSecond: speed)
        )
    }

    static func transferUpload(_ ctx: SFTPUploadChunkContext, chunkSize: Int) async throws {
        let fileHandle = try FileHandle(forReadingFrom: ctx.localURL)
        defer { try? fileHandle.close() }
        let startOffset = UInt64(max(0, ctx.initialOffset))
        try fileHandle.seek(toOffset: startOffset)

        let cursor = UploadChunkCursor(fileHandle: fileHandle, chunkSize: chunkSize, startOffset: startOffset)
        let startTime = ContinuousClock.now
        let windowLimit = max(1, ctx.inFlightWindow)
        var completedBytes: Int64 = 0

        try await withThrowingTaskGroup(of: Int.self) { group in
            var active = 0
            while active < windowLimit, try scheduleNextWrite(into: &group, ctx: ctx, cursor: cursor) {
                active += 1
            }
            while let writtenCount = try await group.next() {
                try Task.checkCancellation()
                active -= 1
                completedBytes += Int64(writtenCount)
                emitUploadProgress(ctx: ctx, completedBytes: completedBytes, startTime: startTime)
                while active < windowLimit, try scheduleNextWrite(into: &group, ctx: ctx, cursor: cursor) {
                    active += 1
                }
            }
        }
        emitUploadProgress(ctx: ctx, completedBytes: completedBytes, startTime: startTime)
    }

    private static func scheduleNextWrite(
        into group: inout ThrowingTaskGroup<Int, Error>,
        ctx: SFTPUploadChunkContext,
        cursor: UploadChunkCursor
    ) throws -> Bool {
        guard let slice = try cursor.nextSlice() else { return false }
        group.addTask {
            try Task.checkCancellation()
            let resp = try await ctx.bridge.send(
                .write(
                    requestID: ctx.bridge.allocateRequestID(),
                    handle: ctx.handle,
                    offset: slice.offset,
                    data: slice.data
                )
            )
            try SFTPService.verifyStatusOKPacket(resp, path: ctx.remotePath.rawValue)
            return slice.data.count
        }
        return true
    }

    private static func emitUploadProgress(
        ctx: SFTPUploadChunkContext,
        completedBytes: Int64,
        startTime: ContinuousClock.Instant
    ) {
        let reported = ctx.initialOffset + completedBytes
        let speed = SFTPService.calculateSpeed(bytes: completedBytes, since: startTime)
        ctx.onProgress(
            TransferProgress(bytesTransferred: reported, totalBytes: ctx.totalBytes, bytesPerSecond: speed)
        )
    }
}
