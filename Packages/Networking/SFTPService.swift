import Foundation
import SparkleCore
import SparkleSecurity

/// SFTP v3 implementation of `RemoteConnection` & `RemoteFileSystem` directly on top of `SSHClientService`.
public actor SFTPService: RemoteConnection, RemoteFileSystem {
    public nonisolated let profile: ConnectionProfile
    private let sshClient: SSHClientService
    var bridge: SFTPChannelBridge?
    let chunkSize = 32 * 1024
    private var pipelineDepth: Int

    public init(profile: ConnectionProfile, sshClient: SSHClientService, pipelineDepth: Int = 8) {
        self.profile = profile
        self.sshClient = sshClient
        self.pipelineDepth = min(16, max(1, pipelineDepth))
    }

    public func updatePipelineDepth(_ depth: Int) {
        pipelineDepth = min(16, max(1, depth))
    }

    public var capabilities: Set<RemoteCapability> {
        [.resumeTransfers, .atomicRename, .posixPermissions, .symlinks, .ptyTerminal, .portForwarding]
    }

    public var connectionState: ConnectionState {
        get async { await sshClient.connectionState }
    }

    public func connect() async throws {
        try await sshClient.connect()
        let channelBridge = try await sshClient.openSFTPBridge()
        let version = try await channelBridge.initializeSFTP()
        guard version >= 3 else {
            channelBridge.close()
            throw AppError.protocolError(code: Int(version), message: "Unsupported SFTP server version \(version)")
        }
        bridge = channelBridge
    }

    public func disconnect(policy: DisconnectPolicy) async throws {
        bridge?.close()
        bridge = nil
        try await sshClient.disconnect(policy: policy)
    }

    public func listDirectory(at path: RemotePath) async throws -> [RemoteFile] {
        let sftp = try requireBridge()
        let openReqID = sftp.allocateRequestID()
        let openResp = try await sftp.send(.opendir(requestID: openReqID, path: path.rawValue))
        let handle = try extractHandle(from: openResp, path: path.rawValue)

        defer {
            Task { [sftp, handle] in
                _ = try? await sftp.send(.close(requestID: sftp.allocateRequestID(), handle: handle))
            }
        }

        var items: [RemoteFile] = []
        while true {
            try Task.checkCancellation()
            let readResp = try await sftp.send(.readdir(requestID: sftp.allocateRequestID(), handle: handle))
            switch readResp {
            case let .name(_, entries):
                for entry in entries where entry.filename != "." && entry.filename != ".." {
                    guard let safeChild = try? PathValidator.canonicalizeRemote(entry.filename, relativeTo: path) else {
                        continue
                    }
                    let perms = entry.attributes.permissions ?? 0o644
                    let mtime = entry.attributes.modificationTime.map { Date(timeIntervalSince1970: TimeInterval($0)) }
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
            case .status(_, .eof, _, _):
                return items
            case let .status(_, code, msg, _):
                throw Self.mapStatusError(code: code, message: msg, path: path.rawValue)
            default:
                throw AppError.protocolError(code: -1, message: "Unexpected READDIR response")
            }
        }
    }

    public func metadata(at path: RemotePath) async throws -> RemoteFileMetadata {
        let sftp = try requireBridge()
        let resp = try await sftp.send(.lstat(requestID: sftp.allocateRequestID(), path: path.rawValue))
        let attrs = try extractAttrs(from: resp, path: path.rawValue)
        let mtime = attrs.modificationTime.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        return RemoteFileMetadata(
            path: path,
            size: Int64(attrs.size ?? 0),
            isDirectory: attrs.isDirectory,
            isSymlink: attrs.isSymlink,
            permissions: (attrs.permissions ?? 0o644) & 0o7777,
            modificationTime: mtime
        )
    }

    public func resolveSymlink(at path: RemotePath) async throws -> RemotePath {
        let sftp = try requireBridge()
        let resp = try await sftp.send(.realpath(requestID: sftp.allocateRequestID(), path: path.rawValue))
        switch resp {
        case let .name(_, entries):
            guard let first = entries.first else {
                throw AppError.fileNotFound(path: path.rawValue)
            }
            return RemotePath(rawValue: first.filename)
        case let .status(_, code, msg, _):
            throw Self.mapStatusError(code: code, message: msg, path: path.rawValue)
        default:
            throw AppError.protocolError(code: -1, message: "Unexpected REALPATH response")
        }
    }

    public func download(
        from remotePath: RemotePath,
        to localURL: URL,
        offset: Int64,
        onProgress: @escaping @Sendable (TransferProgress) -> Void
    ) async throws {
        let sftp = try requireBridge()
        let total = try await metadata(at: remotePath).size
        let openResp = try await sftp.send(
            .open(
                requestID: sftp.allocateRequestID(),
                path: remotePath.rawValue,
                flags: .read,
                attributes: SFTPAttributes()
            )
        )
        let handle = try extractHandle(from: openResp, path: remotePath.rawValue)
        defer {
            Task { [sftp, handle] in
                _ = try? await sftp.send(.close(requestID: sftp.allocateRequestID(), handle: handle))
            }
        }
        let ctx = SFTPDownloadChunkContext(
            bridge: sftp,
            handle: handle,
            remotePath: remotePath,
            localURL: localURL,
            initialOffset: offset,
            totalBytes: total,
            inFlightWindow: max(1, pipelineDepth) * 2,
            onProgress: onProgress
        )
        try await transferDownloadChunks(ctx)
    }

    public func upload(
        from localURL: URL,
        to remotePath: RemotePath,
        offset: Int64,
        onProgress: @escaping @Sendable (TransferProgress) -> Void
    ) async throws {
        let sftp = try requireBridge()
        let attrs = try FileManager.default.attributesOfItem(atPath: localURL.path)
        let total = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let openFlags: SFTPOpenFlags = offset > 0 ? [.write, .create] : [.write, .create, .truncate]
        let openResp = try await sftp.send(
            .open(
                requestID: sftp.allocateRequestID(),
                path: remotePath.rawValue,
                flags: openFlags,
                attributes: SFTPAttributes()
            )
        )
        let handle = try extractHandle(from: openResp, path: remotePath.rawValue)
        defer {
            Task { [sftp, handle] in
                _ = try? await sftp.send(.close(requestID: sftp.allocateRequestID(), handle: handle))
            }
        }
        let ctx = SFTPUploadChunkContext(
            bridge: sftp,
            handle: handle,
            remotePath: remotePath,
            localURL: localURL,
            initialOffset: offset,
            totalBytes: total,
            inFlightWindow: max(1, pipelineDepth) * 2,
            onProgress: onProgress
        )
        try await transferUploadChunks(ctx)
    }

    public func delete(at path: RemotePath, isDirectory: Bool) async throws {
        let sftp = try requireBridge()
        let packet: SFTPPacket = isDirectory
            ? .rmdir(requestID: sftp.allocateRequestID(), path: path.rawValue)
            : .remove(requestID: sftp.allocateRequestID(), path: path.rawValue)
        let resp = try await sftp.send(packet)
        try verifyStatusOK(resp, path: path.rawValue)
    }

    public func rename(from source: RemotePath, to destination: RemotePath) async throws {
        let sftp = try requireBridge()
        let resp = try await sftp.send(
            .rename(requestID: sftp.allocateRequestID(), oldPath: source.rawValue, newPath: destination.rawValue)
        )
        try verifyStatusOK(resp, path: destination.rawValue)
    }

    public func createDirectory(at path: RemotePath) async throws {
        let sftp = try requireBridge()
        let resp = try await sftp.send(
            .mkdir(
                requestID: sftp.allocateRequestID(),
                path: path.rawValue,
                attributes: SFTPAttributes(permissions: 0o755)
            )
        )
        try verifyStatusOK(resp, path: path.rawValue)
    }

    public func setPermissions(_ permissions: UInt32, at path: RemotePath) async throws {
        let sftp = try requireBridge()
        let resp = try await sftp.send(
            .setstat(
                requestID: sftp.allocateRequestID(),
                path: path.rawValue,
                attributes: SFTPAttributes(permissions: permissions & 0o7777)
            )
        )
        try verifyStatusOK(resp, path: path.rawValue)
    }
}
