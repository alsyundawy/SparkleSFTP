import Foundation

/// Authentication methods supported by remote protocols.
public enum AuthMethod: String, Sendable, Codable, CaseIterable, Identifiable {
    case password
    case publicKey
    case sshAgent
    case keyboardInteractive
    case anonymous

    public var id: String { rawValue }
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
        case .connectionTimeout(let host, let seconds):
            return "Connection to \(host) timed out after \(seconds) seconds."
        case .hostUnreachable(let host):
            return "Unable to reach host \(host)."
        case .notConnected:
            return "No active remote connection."
        case .protocolError(let code, let message):
            return "Protocol error (\(code)): \(message)"
        case .unsupportedCapability(let capability):
            return "Remote server does not support \(capability)."
        case .channelStalled(let reason):
            return "SSH channel stalled: \(reason)"
        case .hostKeyUnknown(let host, let port, let fingerprint):
            return "Host key for \(host):\(port) (\(fingerprint)) has not been verified."
        case .hostKeyRejected(let host, let port):
            return "Connection blocked: host key for \(host):\(port) was rejected."
        case .hostKeyMismatch(let host, let expected, let got):
            return "SECURITY ALERT: Host key changed for \(host). Expected \(expected), got \(got)."
        case .hostTrustCorrupted(let host):
            return "Stored host trust record for \(host) is corrupted and requires re-verification."
        case .tlsValidationFailed(let reason):
            return "TLS certificate validation failed: \(reason)"
        case .pathTraversal(let attempted):
            return "Blocked unsafe path traversal attempt: \(attempted)"
        case .symlinkTraversal(let destination):
            return "Blocked destination escaping base directory: \(destination)"
        case .maliciousSymlink(let target):
            return "Blocked unsafe symlink target: \(target)"
        case .authenticationFailed(let method):
            return "Authentication failed using \(method.rawValue)."
        case .credentialNotFound(let service):
            return "Stored credential not found for \(service)."
        case .keychainFailure(let status, let message):
            return "Keychain error (\(status)): \(message)"
        case .biometricAuthenticationFailed(let reason):
            return "Biometric verification failed: \(reason)"
        case .invalidPrivateKey(let reason):
            return "Invalid private key: \(reason)"
        case .fileNotFound(let path):
            return "File or directory not found: \(path)"
        case .transferFailed(let reason):
            return "Transfer failed: \(reason)"
        case .diskFull(let required, let available):
            return "Insufficient disk space (required \(required) bytes, available \(available) bytes)."
        case .permissionDenied(let path):
            return "Permission denied for \(path)."
        case .checksumMismatch(let expected, let actual):
            return "Integrity check failed: expected SHA-256 \(expected), got \(actual)."
        case .partialTransferCorrupted(let expected, let actual):
            return "Partial file mismatch (expected \(expected) bytes, found \(actual) bytes)."
        case .invalidConfiguration(let detail):
            return "Invalid configuration: \(detail)"
        case .planExpired:
            return "Synchronization preview expired. Re-scan before executing."
        case .syncConflict(let path):
            return "Synchronization conflict detected at \(path)."
        case .persistenceFailure(let reason):
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
