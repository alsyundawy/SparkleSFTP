import Foundation
import SparkleCore

/// Security mode options for exporting connection configurations (OWASP & CWE-312 compliance).
public enum ConnectionExportSecurityMode: String, Sendable, Codable, CaseIterable {
    /// Sanitizes all secrets: passwords, keys, and passphrases are omitted. Safe for team sharing.
    case sanitizedWithoutSecrets
    /// Password-protected archive encrypted via AES-256-GCM + PBKDF2-HMAC-SHA256 (100,000 iterations).
    case passwordProtected
    /// Plaintext secrets embedded in base64 within JSON (requires explicit user acknowledgment).
    case plaintextSecrets

    public var localizedKey: String {
        switch self {
        case .sanitizedWithoutSecrets: return "export.mode.sanitized"
        case .passwordProtected: return "export.mode.encrypted"
        case .plaintextSecrets: return "export.mode.plaintext"
        }
    }
}

/// A single exported connection with optional embedded transient secret.
public struct ExportedConnection: Sendable, Codable, Equatable {
    public var profile: ConnectionProfile
    public var groupName: String?
    /// Base64 encoded secret data if exported with credentials; nil if sanitized.
    public var embeddedSecretBase64: String?
    /// Type of embedded secret ("password", "privateKey", "passphrase").
    public var embeddedSecretKind: String?

    public init(
        profile: ConnectionProfile,
        groupName: String? = nil,
        embeddedSecretBase64: String? = nil,
        embeddedSecretKind: String? = nil
    ) {
        self.profile = profile
        self.groupName = groupName
        self.embeddedSecretBase64 = embeddedSecretBase64
        self.embeddedSecretKind = embeddedSecretKind
    }
}

/// Unencrypted native JSON schema for SparkleSFTP connection exports.
public struct SparkleSFTPConnectionExport: Sendable, Codable, Equatable {
    public static let currentSchemaVersion = 1
    public static let generatorIdentifier = "SparkleSFTP for macOS"

    public let schemaVersion: Int
    public let appVersion: String
    public let exportedAt: Date
    public let generator: String
    public var groups: [ServerGroup]
    public var connections: [ExportedConnection]

    public init(
        schemaVersion: Int = SparkleSFTPConnectionExport.currentSchemaVersion,
        appVersion: String = "0.5.0",
        exportedAt: Date = Date(),
        generator: String = SparkleSFTPConnectionExport.generatorIdentifier,
        groups: [ServerGroup] = [],
        connections: [ExportedConnection] = []
    ) {
        self.schemaVersion = schemaVersion
        self.appVersion = appVersion
        self.exportedAt = exportedAt
        self.generator = generator
        self.groups = groups
        self.connections = connections
    }
}

/// Tamper-resistant encrypted archive container for password-protected exports.
public struct SparkleSFTPEncryptedArchive: Sendable, Codable, Equatable {
    public static let formatIdentifier = "sparklesftp-encrypted-archive"
    public static let currentVersion = 1
    public static let defaultIterations = 100_000

    public let format: String
    public let version: Int
    public let kdf: String
    public let iterations: Int
    public let saltBase64: String
    public let nonceBase64: String
    public let tagBase64: String
    public let ciphertextBase64: String

    public init(
        format: String = SparkleSFTPEncryptedArchive.formatIdentifier,
        version: Int = SparkleSFTPEncryptedArchive.currentVersion,
        kdf: String = "PBKDF2-HMAC-SHA256",
        iterations: Int = SparkleSFTPEncryptedArchive.defaultIterations,
        saltBase64: String,
        nonceBase64: String,
        tagBase64: String,
        ciphertextBase64: String
    ) {
        self.format = format
        self.version = version
        self.kdf = kdf
        self.iterations = iterations
        self.saltBase64 = saltBase64
        self.nonceBase64 = nonceBase64
        self.tagBase64 = tagBase64
        self.ciphertextBase64 = ciphertextBase64
    }
}
