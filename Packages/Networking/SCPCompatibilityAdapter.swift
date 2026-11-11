import Foundation
import SparkleCore
import SparkleSecurity

/// SCP compatibility fallback activated when SSH server lacks the SFTP subsystem (DEAD-002, MAINT-004).
public actor SCPCompatibilityAdapter: RemoteConnection, RemoteFileSystem {
    public nonisolated let profile: ConnectionProfile
    private let sshService: SSHClientService

    public init(profile: ConnectionProfile, sshService: SSHClientService) {
        self.profile = profile
        self.sshService = sshService
    }

    public var capabilities: Set<RemoteCapability> {
        [.posixPermissions]
    }

    public var connectionState: ConnectionState {
        get async { await sshService.connectionState }
    }

    public func connect() async throws {
        try await sshService.connect()
    }

    public func disconnect(policy: DisconnectPolicy) async throws {
        try await sshService.disconnect(policy: policy)
    }

    /// Escapes a POSIX shell argument safely using strict single-quoting (`SEC-007`).
    public static func escapePOSIXSingleQuoted(_ raw: String) throws -> String {
        if raw.contains("\0") {
            throw AppError.pathTraversal(attempted: raw)
        }
        let escaped = raw.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }

    public func listDirectory(at path: RemotePath) async throws -> [RemoteFile] {
        let quoted = try Self.escapePOSIXSingleQuoted(path.rawValue)
        let result = try await sshService.executeCommand("LC_ALL=C ls -la \(quoted)")
        guard result.exitCode == 0 else {
            throw AppError.protocolError(code: result.exitCode, message: result.stderr)
        }
        return FTPListingParser.parse(listing: result.stdout, directory: path)
    }

    public func metadata(at path: RemotePath) async throws -> RemoteFileMetadata {
        let quoted = try Self.escapePOSIXSingleQuoted(path.rawValue)
        let result = try await sshService.executeCommand(
            "LC_ALL=C stat -c '%s %f %Y' \(quoted) 2>/dev/null || LC_ALL=C stat -f '%z %Xp %m' \(quoted)"
        )
        guard result.exitCode == 0 else {
            throw AppError.fileNotFound(path: path.rawValue)
        }
        let parts = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
        guard parts.count >= 3,
              let size = Int64(parts[0]),
              let rawMode = UInt32(parts[1], radix: 16),
              let mtime = TimeInterval(parts[2])
        else {
            throw AppError.protocolError(code: -1, message: "Unable to parse remote stat output")
        }
        let isDir = (rawMode & 0o170000) == 0o040000
        let isLink = (rawMode & 0o170000) == 0o120000
        return RemoteFileMetadata(
            path: path,
            size: size,
            isDirectory: isDir,
            isSymlink: isLink,
            permissions: rawMode & 0o7777,
            modificationTime: Date(timeIntervalSince1970: mtime)
        )
    }

    public func resolveSymlink(at path: RemotePath) async throws -> RemotePath {
        let quoted = try Self.escapePOSIXSingleQuoted(path.rawValue)
        let result = try await sshService.executeCommand("readlink -f \(quoted) || realpath \(quoted)")
        guard result.exitCode == 0 else {
            throw AppError.fileNotFound(path: path.rawValue)
        }
        let resolved = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return RemotePath(rawValue: resolved)
    }

    public func download(
        from remotePath: RemotePath,
        to localURL: URL,
        offset: Int64,
        onProgress: @escaping @Sendable (TransferProgress) -> Void
    ) async throws {
        let quoted = try Self.escapePOSIXSingleQuoted(remotePath.rawValue)
        let meta = try await metadata(at: remotePath)
        let command = offset > 0 ? "tail -c +\(offset + 1) \(quoted) | base64" : "base64 < \(quoted)"
        let result = try await sshService.executeCommand(command)
        guard result.exitCode == 0 else {
            throw AppError.transferFailed(reason: result.stderr)
        }
        let cleanB64 = result.stdout.components(separatedBy: .whitespacesAndNewlines).joined()
        guard let decoded = Data(base64Encoded: cleanB64) else {
            throw AppError.transferFailed(reason: "Corrupted base64 stream over SCP fallback")
        }

        if offset > 0, FileManager.default.fileExists(atPath: localURL.path) {
            let handle = try FileHandle(forUpdating: localURL)
            defer { try? handle.close() }
            try handle.seek(toOffset: UInt64(offset))
            try handle.write(contentsOf: decoded)
        } else {
            try decoded.write(to: localURL, options: [.atomic])
        }

        onProgress(
            TransferProgress(
                bytesTransferred: offset + Int64(decoded.count),
                totalBytes: max(meta.size, offset + Int64(decoded.count)),
                bytesPerSecond: Int64(decoded.count)
            )
        )
    }

    public func upload(
        from localURL: URL,
        to remotePath: RemotePath,
        offset: Int64,
        onProgress: @escaping @Sendable (TransferProgress) -> Void
    ) async throws {
        let quoted = try Self.escapePOSIXSingleQuoted(remotePath.rawValue)
        let attrs = try FileManager.default.attributesOfItem(atPath: localURL.path)
        let totalSize = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let handle = try FileHandle(forReadingFrom: localURL)
        defer { try? handle.close() }

        let clampedOffset = max(0, min(offset, totalSize))
        try handle.seek(toOffset: UInt64(clampedOffset))

        if totalSize == 0, clampedOffset == 0 {
            let result = try await sshService.executeCommand(": > \(quoted)")
            guard result.exitCode == 0 else {
                throw AppError.transferFailed(reason: result.stderr)
            }
            onProgress(TransferProgress(bytesTransferred: 0, totalBytes: 0, bytesPerSecond: 0))
            return
        }

        let chunkLimit = 24 * 1024
        var sent = clampedOffset
        var isFirstChunk = true
        while true {
            try Task.checkCancellation()
            let chunk = try handle.read(upToCount: chunkLimit) ?? Data()
            if chunk.isEmpty {
                break
            }
            let b64 = chunk.base64EncodedString()
            let redirectOperator = (isFirstChunk && clampedOffset == 0) ? ">" : ">>"
            let command = "printf '%s' '\(b64)' | base64 -d \(redirectOperator) \(quoted)"
            let result = try await sshService.executeCommand(command)
            guard result.exitCode == 0 else {
                throw AppError.transferFailed(reason: result.stderr)
            }
            isFirstChunk = false
            sent += Int64(chunk.count)
            onProgress(
                TransferProgress(
                    bytesTransferred: sent,
                    totalBytes: totalSize,
                    bytesPerSecond: Int64(chunk.count)
                )
            )
        }
    }

    public func delete(at path: RemotePath, isDirectory: Bool) async throws {
        let quoted = try Self.escapePOSIXSingleQuoted(path.rawValue)
        let cmd = isDirectory ? "rmdir \(quoted)" : "rm -f \(quoted)"
        let result = try await sshService.executeCommand(cmd)
        guard result.exitCode == 0 else {
            throw AppError.protocolError(code: result.exitCode, message: result.stderr)
        }
    }

    public func rename(from source: RemotePath, to destination: RemotePath) async throws {
        let src = try Self.escapePOSIXSingleQuoted(source.rawValue)
        let dst = try Self.escapePOSIXSingleQuoted(destination.rawValue)
        let result = try await sshService.executeCommand("mv -f \(src) \(dst)")
        guard result.exitCode == 0 else {
            throw AppError.protocolError(code: result.exitCode, message: result.stderr)
        }
    }

    public func createDirectory(at path: RemotePath) async throws {
        let quoted = try Self.escapePOSIXSingleQuoted(path.rawValue)
        let result = try await sshService.executeCommand("mkdir -p \(quoted)")
        guard result.exitCode == 0 else {
            throw AppError.protocolError(code: result.exitCode, message: result.stderr)
        }
    }

    public func setPermissions(_ permissions: UInt32, at path: RemotePath) async throws {
        let quoted = try Self.escapePOSIXSingleQuoted(path.rawValue)
        let octal = String(permissions & 0o7777, radix: 8)
        let result = try await sshService.executeCommand("chmod \(octal) \(quoted)")
        guard result.exitCode == 0 else {
            throw AppError.protocolError(code: result.exitCode, message: result.stderr)
        }
    }
}
