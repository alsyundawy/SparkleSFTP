import Foundation

/// Authentication methods supported by remote protocols.
public enum AuthMethod: String, Sendable, Codable, CaseIterable, Identifiable {
    case password
    case publicKey
    case sshAgent
    case keyboardInteractive
    case anonymous

    public var id: String {
        rawValue
    }
}

/// Structured, Sendable error taxonomy across networking, security, transfer, sync, and persistence layers.
public enum AppError: Error, Sendable, LocalizedError, Equatable {
    // MARK: - Network & Connection

    case connectionTimeout(host: String, seconds: Int)
    case hostUnreachable(host: String)
    case notConnected
    case protocolError(code: Int, message: String)
    case unsupportedCapability(String)
    case channelStalled(reason: String)

    // MARK: - Trust & Security

    case hostKeyUnknown(host: String, port: Int, fingerprint: String)
    case hostKeyRejected(host: String, port: Int)
    case hostKeyMismatch(host: String, expected: String, got: String)
    case hostTrustCorrupted(host: String)
    case tlsValidationFailed(reason: String)
    case pathTraversal(attempted: String)
    case symlinkTraversal(destination: String)
    case maliciousSymlink(target: String)
    case maliciousCommandInjection(command: String)

    // MARK: - Authentication & Keychain

    case authenticationFailed(method: AuthMethod)
    case credentialNotFound(service: String)
    case keychainFailure(status: Int32, message: String)
    case biometricAuthenticationFailed(reason: String)
    case invalidPrivateKey(reason: String)

    // MARK: - File & Transfer

    case fileNotFound(path: String)
    case transferFailed(reason: String)
    case diskFull(requiredBytes: Int64, availableBytes: Int64)
    case permissionDenied(path: String)
    case checksumMismatch(expected: String, actual: String)
    case partialTransferCorrupted(bytesExpected: Int64, bytesActual: Int64)
    case invalidConfiguration(String)

    // MARK: - Sync & Persistence

    case planExpired
    case syncConflict(path: String)
    case persistenceFailure(reason: String)

    public var errorDescription: String? {
        switch self {
        case let .connectionTimeout(host, seconds):
            return "Connection to \(host) timed out after \(seconds) seconds."
        case let .hostUnreachable(host):
            return "Unable to reach host \(host)."
        case .notConnected:
            return "No active remote connection."
        case let .protocolError(code, message):
            return "Protocol error (\(code)): \(message)"
        case let .unsupportedCapability(capability):
            return "Remote server does not support \(capability)."
        case let .channelStalled(reason):
            return "SSH channel stalled: \(reason)"
        case let .hostKeyUnknown(host, port, fingerprint):
            return "Host key for \(host):\(port) (\(fingerprint)) has not been verified."
        case let .hostKeyRejected(host, port):
            return "Connection blocked: host key for \(host):\(port) was rejected."
        case let .hostKeyMismatch(host, expected, got):
            return "SECURITY ALERT: Host key changed for \(host). Expected \(expected), got \(got)."
        case let .hostTrustCorrupted(host):
            return "Stored host trust record for \(host) is corrupted and requires re-verification."
        case let .tlsValidationFailed(reason):
            return "TLS certificate validation failed: \(reason)"
        case let .pathTraversal(attempted):
            return "Blocked unsafe path traversal attempt: \(attempted)"
        case let .symlinkTraversal(destination):
            return "Blocked destination escaping base directory: \(destination)"
        case let .maliciousSymlink(target):
            return "Blocked unsafe symlink target: \(target)"
        case let .maliciousCommandInjection(command):
            return "Blocked unsafe shell command injection: \(command)"
        case let .authenticationFailed(method):
            return "Authentication failed using \(method.rawValue)."
        case let .credentialNotFound(service):
            return "Stored credential not found for \(service)."
        case let .keychainFailure(status, message):
            return "Keychain error (\(status)): \(message)"
        case let .biometricAuthenticationFailed(reason):
            return "Biometric verification failed: \(reason)"
        case let .invalidPrivateKey(reason):
            return "Invalid private key: \(reason)"
        case let .fileNotFound(path):
            return "File or directory not found: \(path)"
        case let .transferFailed(reason):
            return "Transfer failed: \(reason)"
        case let .diskFull(required, available):
            return "Insufficient disk space (required \(required) bytes, available \(available) bytes)."
        case let .permissionDenied(path):
            return "Permission denied for \(path)."
        case let .checksumMismatch(expected, actual):
            return "Integrity check failed: expected SHA-256 \(expected), got \(actual)."
        case let .partialTransferCorrupted(expected, actual):
            return "Partial file mismatch (expected \(expected) bytes, found \(actual) bytes)."
        case let .invalidConfiguration(detail):
            return "Invalid configuration: \(detail)"
        case .planExpired:
            return "Synchronization preview expired. Re-scan before executing."
        case let .syncConflict(path):
            return "Synchronization conflict detected at \(path)."
        case let .persistenceFailure(reason):
            return "Storage error: \(reason)"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .hostKeyMismatch:
            return "Verify the new server fingerprint out-of-band before resetting host trust."
        case .tlsValidationFailed:
            return "Check the server certificate chain, hostname, and expiration date."
        case .planExpired:
            return "Run Dry-Run Preview again so changes reflect the latest remote state."
        case .authenticationFailed, .credentialNotFound:
            return "Update the credentials or key reference in Connection Settings."
        default:
            return nil
        }
    }

    /// Indicates whether the error represents an OS/POSIX permission denied code.
    public var isPermissionDenied: Bool {
        if case .permissionDenied = self {
            return true
        }
        return false
    }

    /// Errors that should not be blindly retried with exponential backoff.
    public var isNonRetryableSecurityOrAuthError: Bool {
        switch self {
        case .authenticationFailed,
             .credentialNotFound,
             .hostKeyRejected,
             .hostKeyMismatch,
             .hostTrustCorrupted,
             .tlsValidationFailed,
             .pathTraversal,
             .symlinkTraversal,
             .maliciousSymlink,
             .maliciousCommandInjection,
             .biometricAuthenticationFailed,
             .invalidPrivateKey,
             .permissionDenied,
             .checksumMismatch:
            return true
        default:
            return false
        }
    }
}
