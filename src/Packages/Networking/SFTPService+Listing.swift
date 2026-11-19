import Foundation
import SparkleCore
import SparkleSecurity

extension SFTPService {
    /// Streams directory contents in memory-bounded batches using an AsyncSequence (TD-13, Task 3.6).
    public func streamDirectory(
        at path: RemotePath,
        batchSize: Int = 500
    ) -> AsyncThrowingStream<[RemoteFile], Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let sftp = try self.requireBridge()
                    let openReqID = sftp.allocateRequestID()
                    let openResp = try await sftp.send(.opendir(requestID: openReqID, path: path.rawValue))
                    let handle = try self.extractHandle(from: openResp, path: path.rawValue)
                    try await self.executeDirectoryStream(
                        sftp: sftp,
                        handle: handle,
                        path: path,
                        batchSize: batchSize,
                        continuation: continuation
                    )
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    private func executeDirectoryStream(
        sftp: SFTPChannelBridge,
        handle: Data,
        path: RemotePath,
        batchSize: Int,
        continuation: AsyncThrowingStream<[RemoteFile], Error>.Continuation
    ) async throws {
        var currentBatch: [RemoteFile] = []
        currentBatch.reserveCapacity(batchSize)

        do {
            while true {
                try Task.checkCancellation()
                let readResp = try await sftp.send(
                    .readdir(requestID: sftp.allocateRequestID(), handle: handle)
                )
                switch readResp {
                case let .name(_, entries):
                    let parsed = self.convertNameEntries(entries, path: path)
                    currentBatch.append(contentsOf: parsed)
                    if currentBatch.count >= batchSize {
                        continuation.yield(currentBatch)
                        currentBatch.removeAll(keepingCapacity: true)
                    }
                case .status(_, .eof, _, _):
                    if !currentBatch.isEmpty {
                        continuation.yield(currentBatch)
                    }
                    await self.closeHandle(handle, on: sftp)
                    continuation.finish()
                    return
                case let .status(_, code, msg, _):
                    throw Self.mapStatusError(code: code, message: msg, path: path.rawValue)
                default:
                    throw AppError.protocolError(code: -1, message: "Unexpected READDIR response")
                }
            }
        } catch {
            await self.closeHandle(handle, on: sftp)
            throw error
        }
    }

    public func listDirectory(at path: RemotePath) async throws -> [RemoteFile] {
        let sftp = try requireBridge()
        let openReqID = sftp.allocateRequestID()
        let openResp = try await sftp.send(.opendir(requestID: openReqID, path: path.rawValue))
        let handle = try extractHandle(from: openResp, path: path.rawValue)

        var items: [RemoteFile] = []
        do {
            while true {
                try Task.checkCancellation()
                let readResp = try await sftp.send(
                    .readdir(requestID: sftp.allocateRequestID(), handle: handle)
                )
                switch readResp {
                case let .name(_, entries):
                    let parsed = convertNameEntries(entries, path: path)
                    items.append(contentsOf: parsed)
                case .status(_, .eof, _, _):
                    await closeHandle(handle, on: sftp)
                    return items
                case let .status(_, code, msg, _):
                    throw Self.mapStatusError(code: code, message: msg, path: path.rawValue)
                default:
                    throw AppError.protocolError(code: -1, message: "Unexpected READDIR response")
                }
            }
        } catch {
            await closeHandle(handle, on: sftp)
            throw error
        }
    }

    private func convertNameEntries(_ entries: [SFTPNameEntry], path: RemotePath) -> [RemoteFile] {
        var items: [RemoteFile] = []
        for entry in entries where entry.filename != "." && entry.filename != ".." {
            guard let safeChild = try? PathValidator.canonicalizeRemote(
                entry.filename,
                relativeTo: path
            ) else {
                continue
            }
            let defaultPerms: UInt32 = entry.attributes.isDirectory ? 0o755 : 0o644
            let perms = entry.attributes.permissions ?? defaultPerms
            let mtime = entry.attributes.modificationTime
                .map { Date(timeIntervalSince1970: TimeInterval($0)) }
            items.append(
                RemoteFile(
                    name: entry.filename,
                    path: safeChild,
                    size: Int64(entry.attributes.size ?? 0),
                    isDirectory: entry.attributes.isDirectory,
                    isSymlink: entry.attributes.isSymlink,
                    permissions: perms & 0o7777,
                    modificationTime: mtime,
                    ownerID: entry.attributes.uid,
                    groupID: entry.attributes.gid
                )
            )
        }
        return items
    }
}
