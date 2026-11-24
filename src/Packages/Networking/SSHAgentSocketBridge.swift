import Foundation
import SparkleCore
import SparkleSecurity

/// Bridges local OpenSSH agent (`SSH_AUTH_SOCK`) to remote sessions with path validation.
public final class SSHAgentSocketBridge: Sendable {
    public enum BridgeError: Error, LocalizedError {
        case socketUnavailable
        case invalidSocketPath(String)
        case connectionFailed(String)

        public var errorDescription: String? {
            switch self {
            case .socketUnavailable:
                return "SSH agent socket ($SSH_AUTH_SOCK) is unavailable or not configured."
            case .invalidSocketPath(let path):
                return "SSH agent socket path is invalid or untrusted: \(path)"
            case .connectionFailed(let reason):
                return "Failed connecting to local SSH agent: \(reason)"
            }
        }
    }

    public static let shared = SSHAgentSocketBridge()

    private init() {}

    /// Validates that the active `SSH_AUTH_SOCK` is a genuine Unix domain socket located in a safe path.
    public func validateSocketPath(_ path: String) throws {
        guard !path.isEmpty else {
            throw BridgeError.socketUnavailable
        }

        // Validate that path does not contain traversal segments
        if path.contains("..") {
            throw BridgeError.invalidSocketPath(path)
        }

        var statBuf = stat()
        guard lstat(path, &statBuf) == 0 else {
            throw BridgeError.invalidSocketPath("Cannot stat socket path")
        }

        // Ensure it is not a symlink pointing to an unexpected location (CWE-59)
        if (statBuf.st_mode & S_IFMT) == S_IFLNK {
            var resolved = [CChar](repeating: 0, count: Int(PATH_MAX))
            guard realpath(path, &resolved) != nil else {
                throw BridgeError.invalidSocketPath("Cannot resolve socket symlink")
            }
            let len = resolved.firstIndex(of: 0) ?? resolved.count
            let byteSlice = resolved.prefix(len).map { UInt8(bitPattern: $0) }
            guard let resolvedStr = String(bytes: byteSlice, encoding: .utf8) else {
                throw BridgeError.invalidSocketPath("Cannot decode resolved socket symlink")
            }
            guard stat(resolvedStr, &statBuf) == 0,
                  (statBuf.st_mode & S_IFMT) == S_IFSOCK,
                  statBuf.st_uid == getuid() else {
                throw BridgeError.invalidSocketPath("Resolved path is not an owned Unix domain socket")
            }
        } else if (statBuf.st_mode & S_IFMT) != S_IFSOCK || statBuf.st_uid != getuid() {
            throw BridgeError.invalidSocketPath("Target file is not an owned Unix domain socket")
        }
    }

    /// Checks if agent forwarding can be safely established on this machine.
    public var canForwardAgent: Bool {
        guard let path = SSHAgentAuthHelper.socketPath else { return false }
        do {
            try validateSocketPath(path)
            return true
        } catch {
            DiagnosticsLogger.security
                .warning("SSH agent socket rejected: \(error.localizedDescription, privacy: .private)")
            return false
        }
    }
}
