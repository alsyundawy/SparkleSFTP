import Foundation

public enum ProtocolType: String, Sendable, Codable, CaseIterable, Identifiable {
    case sftp
    case ftpsExplicit
    case ftpsImplicit
    case ftp
    case scp

    public var id: String { rawValue }

    public var defaultPort: Int {
        switch self {
        case .sftp, .scp:
            return 22
        case .ftpsExplicit, .ftp:
            return 21
        case .ftpsImplicit:
            return 990
        }
    }

    public var displayName: String {
        switch self {
        case .sftp: return "SFTP (SSH)"
        case .ftpsExplicit: return "FTPS (Explicit TLS)"
        case .ftpsImplicit: return "FTPS (Implicit TLS)"
        case .ftp: return "FTP (Plaintext)"
        case .scp: return "SCP (SSH Fallback)"
        }
    }

    public var isEncryptedByDefault: Bool {
        self != .ftp
    }
}

public enum RemoteCapability: String, Sendable, Hashable, CaseIterable {
    case resumeTransfers
    case atomicRename
    case posixPermissions
    case symlinks
    case ptyTerminal
    case portForwarding
    case sha256ChecksumCommand
}

public struct RemoteFile: Identifiable, Sendable, Hashable {
    public var id: String { path.rawValue }
    public let name: String
    public let path: RemotePath
    public let size: Int64
    public let isDirectory: Bool
    public let isSymlink: Bool
    public let symlinkTarget: String?
    public let permissions: UInt32
    public let modificationTime: Date?
    public let ownerID: UInt32?
    public let groupID: UInt32?

    public init(
        name: String,
        path: RemotePath,
        size: Int64,
        isDirectory: Bool,
        isSymlink: Bool = false,
        symlinkTarget: String? = nil,
        permissions: UInt32 = 0o644,
        modificationTime: Date? = nil,
        ownerID: UInt32? = nil,
        groupID: UInt32? = nil
    ) {
        self.name = name
        self.path = path
        self.size = max(0, size)
        self.isDirectory = isDirectory
        self.isSymlink = isSymlink
        self.symlinkTarget = symlinkTarget
        self.permissions = permissions
        self.modificationTime = modificationTime
        self.ownerID = ownerID
        self.groupID = groupID
    }
}

public struct RemoteFileMetadata: Sendable, Equatable {
    public let path: RemotePath
    public let size: Int64
    public let isDirectory: Bool
    public let isSymlink: Bool
    public let permissions: UInt32
    public let modificationTime: Date?
    public let inodeHint: String?

    public init(
        path: RemotePath,
        size: Int64,
        isDirectory: Bool,
        isSymlink: Bool = false,
        permissions: UInt32 = 0o644,
        modificationTime: Date? = nil,
        inodeHint: String? = nil
    ) {
        self.path = path
        self.size = max(0, size)
        self.isDirectory = isDirectory
        self.isSymlink = isSymlink
        self.permissions = permissions
        self.modificationTime = modificationTime
        self.inodeHint = inodeHint
    }
}

/// Complete 6-state TOFU trust lifecycle (LOG-001).
public enum HostTrustState: Sendable, Equatable {
    case unknown
    case pendingUserDecision(fingerprint: String)
    case trusted(fingerprint: String, since: Date)
    case rejected
    case mismatch(expected: String, got: String)
    case corrupted
}

public struct HostKeyChallenge: Identifiable, Sendable, Equatable {
    public var id: String { "\(host):\(port):\(fingerprintSHA256)" }
    public let host: String
    public let port: Int
    public let algorithm: String
    public let fingerprintSHA256: String
    public let previousFingerprintSHA256: String?

    public var isMismatch: Bool {
        previousFingerprintSHA256 != nil
    }

    public init(
        host: String,
        port: Int,
        algorithm: String,
        fingerprintSHA256: String,
        previousFingerprintSHA256: String? = nil
    ) {
        self.host = host
        self.port = port
        self.algorithm = algorithm
        self.fingerprintSHA256 = fingerprintSHA256
        self.previousFingerprintSHA256 = previousFingerprintSHA256
    }
}

public struct TLSCertificateInfo: Sendable, Equatable {
    public let host: String
    public let subject: String
    public let issuer: String
    public let sha256Fingerprint: String
    public let validFrom: Date?
    public let validUntil: Date?
    public let isTrusted: Bool

    public init(
        host: String,
        subject: String,
        issuer: String,
        sha256Fingerprint: String,
        validFrom: Date?,
        validUntil: Date?,
        isTrusted: Bool
    ) {
        self.host = host
        self.subject = subject
        self.issuer = issuer
        self.sha256Fingerprint = sha256Fingerprint
        self.validFrom = validFrom
        self.validUntil = validUntil
        self.isTrusted = isTrusted
    }
}
