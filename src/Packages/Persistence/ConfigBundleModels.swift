import Foundation
import SparkleCore

/// Scope options for exporting configuration bundles in SparkleSFTP v0.6.0.
public struct ConfigExportScope: OptionSet, Sendable, Codable, Hashable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let profiles = ConfigExportScope(rawValue: 1 << 0)
    public static let groups = ConfigExportScope(rawValue: 1 << 1)
    public static let bookmarks = ConfigExportScope(rawValue: 1 << 2)
    public static let pathHistory = ConfigExportScope(rawValue: 1 << 3)
    public static let snippets = ConfigExportScope(rawValue: 1 << 4)
    public static let portForwarding = ConfigExportScope(rawValue: 1 << 5)
    public static let settings = ConfigExportScope(rawValue: 1 << 6)
    public static let customThemes = ConfigExportScope(rawValue: 1 << 7)

    public static let all: ConfigExportScope = [
        .profiles, .groups, .bookmarks, .pathHistory, .snippets,
        .portForwarding, .settings, .customThemes
    ]

    public static let defaultConnectionsOnly: ConfigExportScope = [.profiles, .groups]
}

/// Conflict resolution policy when importing configuration bundles into existing stores.
public enum ConfigImportConflictPolicy: String, Sendable, Codable, CaseIterable {
    case skipExisting
    case overwrite
    case keepBoth
    case mergeGroups

    public var localizedKey: String {
        switch self {
        case .skipExisting: return "import.bundle.policy.skip"
        case .overwrite: return "import.bundle.policy.overwrite"
        case .keepBoth: return "import.bundle.policy.keepBoth"
        case .mergeGroups: return "import.bundle.policy.mergeGroups"
        }
    }
}

/// Representation of a custom theme exported within a config bundle.
public struct SparkleCustomThemeExport: Identifiable, Sendable, Codable, Equatable {
    public let id: UUID
    public var name: String
    public var paletteJSON: String

    public init(id: UUID = UUID(), name: String, paletteJSON: String) {
        self.id = id
        self.name = name
        self.paletteJSON = paletteJSON
    }
}

/// Integrity digest block for configuration bundles (F-01).
public struct ConfigBundleIntegrity: Sendable, Codable, Equatable {
    public let alg: String
    public let digest: String

    public init(alg: String = "sha256", digest: String) {
        self.alg = alg
        self.digest = digest
    }
}

/// Payload payload containing all exported components (F-01).
public struct ConfigBundlePayload: Sendable, Codable, Equatable {
    public var profiles: [ConnectionProfile]
    public var groups: [ServerGroup]
    public var bookmarks: [BookmarkItem]
    public var pathHistory: [PathHistoryItem]
    public var snippets: [CommandSnippet]
    public var portForwardingRules: [PortForwardingRule]
    public var settings: [String: String]
    public var customThemes: [SparkleCustomThemeExport]

    public init(
        profiles: [ConnectionProfile] = [],
        groups: [ServerGroup] = [],
        bookmarks: [BookmarkItem] = [],
        pathHistory: [PathHistoryItem] = [],
        snippets: [CommandSnippet] = [],
        portForwardingRules: [PortForwardingRule] = [],
        settings: [String: String] = [:],
        customThemes: [SparkleCustomThemeExport] = []
    ) {
        self.profiles = profiles
        self.groups = groups
        self.bookmarks = bookmarks
        self.pathHistory = pathHistory
        self.snippets = snippets
        self.portForwardingRules = portForwardingRules
        self.settings = settings
        self.customThemes = customThemes
    }
}

/// SparkleSFTP v0.6.0 Portable Configuration Bundle (Format A: Plaintext JSON).
public struct SparkleConfigBundle: Sendable, Codable, Equatable {
    public static let currentMagic = "sparklesftp.config"
    public static let currentSchemaVersion = 1
    public static let currentAppVersion = "0.6.0"
    public static let maxFileSizeBytes = 25 * 1024 * 1024 // 25 MB cap (CWE-400)
    public static let maxProfileCount = 10000
    public static let maxBookmarkCount = 50000

    public let magic: String
    public let schemaVersion: Int
    public let kind: String
    public let appVersion: String
    public let createdAt: Date
    public var payload: ConfigBundlePayload
    public var integrity: ConfigBundleIntegrity

    public init(
        magic: String = SparkleConfigBundle.currentMagic,
        schemaVersion: Int = SparkleConfigBundle.currentSchemaVersion,
        kind: String = "full",
        appVersion: String = SparkleConfigBundle.currentAppVersion,
        createdAt: Date = Date(),
        payload: ConfigBundlePayload,
        integrity: ConfigBundleIntegrity
    ) {
        self.magic = magic
        self.schemaVersion = schemaVersion
        self.kind = kind
        self.appVersion = appVersion
        self.createdAt = createdAt
        self.payload = payload
        self.integrity = integrity
    }
}

/// Binary header representation for encrypted `.sparklevault` archives (Format B).
public struct SparkleVaultHeader: Sendable, Equatable {
    public static let magicASCII = "SPKVAULT1"
    public static var magicBytes: [UInt8] {
        Array(magicASCII.utf8)
    }

    public static let headerLength = 46
    public static let defaultIterations: UInt32 = 600_000
    public static let minIterations: UInt32 = 10000
    public static let saltByteCount = 16
    public static let nonceByteCount = 12
    public static let tagByteCount = 16
    public static let kdfPBKDF2HMACSHA256: UInt8 = 1

    public let kdfId: UInt8
    public let iterations: UInt32
    public let salt: Data
    public let nonce: Data
    public let ciphertextLength: UInt32

    public init(
        kdfId: UInt8 = SparkleVaultHeader.kdfPBKDF2HMACSHA256,
        iterations: UInt32 = SparkleVaultHeader.defaultIterations,
        salt: Data,
        nonce: Data,
        ciphertextLength: UInt32
    ) {
        self.kdfId = kdfId
        self.iterations = iterations
        self.salt = salt
        self.nonce = nonce
        self.ciphertextLength = ciphertextLength
    }

    /// Serializes the 46-byte binary header.
    public func serialize() -> Data {
        var data = Data()
        data.append(contentsOf: SparkleVaultHeader.magicASCII.utf8) // 9 bytes
        data.append(kdfId) // 1 byte
        var iterBigEndian = iterations.bigEndian
        data.append(Data(bytes: &iterBigEndian, count: 4)) // 4 bytes
        data.append(salt) // 16 bytes
        data.append(nonce) // 12 bytes
        var lenBigEndian = ciphertextLength.bigEndian
        data.append(Data(bytes: &lenBigEndian, count: 4)) // 4 bytes
        return data
    }

    /// Parses the 46-byte header from the beginning of a data buffer.
    public static func parse(from data: Data) throws -> SparkleVaultHeader {
        guard data.count >= headerLength else {
            throw AppError.persistenceFailure(reason: "Invalid vault file: payload smaller than header length")
        }
        let magicData = data.prefix(9)
        guard let magicStr = String(data: magicData, encoding: .utf8),
              magicStr == magicASCII
        else {
            throw AppError.persistenceFailure(reason: "Invalid vault file magic identifier")
        }
        let kdfId = data[9]
        guard kdfId == kdfPBKDF2HMACSHA256 else {
            throw AppError.persistenceFailure(reason: "Unsupported vault KDF algorithm identifier: \(kdfId)")
        }
        let iterData = data.subdata(in: 10 ..< 14)
        let iterations = iterData.withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
        guard iterations >= minIterations else {
            throw AppError
                .persistenceFailure(
                    reason: "Vault iterations below safety threshold (\(iterations) < \(minIterations))"
                )
        }
        let salt = data.subdata(in: 14 ..< 30)
        let nonce = data.subdata(in: 30 ..< 42)
        let lenData = data.subdata(in: 42 ..< 46)
        let ciphertextLength = lenData.withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian

        return SparkleVaultHeader(
            kdfId: kdfId,
            iterations: iterations,
            salt: salt,
            nonce: nonce,
            ciphertextLength: ciphertextLength
        )
    }
}
