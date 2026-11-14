import Foundation
import SparkleCore

/// Recognized format of an incoming configuration source file.
public enum ConfigSourceFormat: String, Sendable, Codable {
    case sparkleVault = "SparkleSFTP Vault (.sparklevault)"
    case sparkleConfig = "SparkleSFTP Bundle (.sparkleconfig)"
    case legacyExport = "SparkleSFTP Legacy Export (.json)"
    case fileZillaXML = "FileZilla Site Manager (.xml)"
    case winSCPINI = "WinSCP Sessions (.ini)"
    case openSSHConfig = "OpenSSH Configuration (~/.ssh/config)"
    case unknown = "Unknown Format"
}

/// A structured plan summarizing incoming items and conflict resolutions prior to commit.
public struct ConfigImportPlan: Sendable {
    public let bundle: SparkleConfigBundle
    public let sourceFormat: ConfigSourceFormat
    public let newProfiles: [ConnectionProfile]
    public let conflictingProfiles: [(existing: ConnectionProfile, imported: ConnectionProfile)]
    public let newGroups: [ServerGroup]
    public let newBookmarks: [BookmarkItem]
    public let newSnippets: [CommandSnippet]
    public let integrityVerified: Bool

    public init(
        bundle: SparkleConfigBundle,
        sourceFormat: ConfigSourceFormat,
        newProfiles: [ConnectionProfile],
        conflictingProfiles: [(existing: ConnectionProfile, imported: ConnectionProfile)],
        newGroups: [ServerGroup],
        newBookmarks: [BookmarkItem] = [],
        newSnippets: [CommandSnippet] = [],
        integrityVerified: Bool = true
    ) {
        self.bundle = bundle
        self.sourceFormat = sourceFormat
        self.newProfiles = newProfiles
        self.conflictingProfiles = conflictingProfiles
        self.newGroups = newGroups
        self.newBookmarks = newBookmarks
        self.newSnippets = newSnippets
        self.integrityVerified = integrityVerified
    }
}

/// Result metrics and warnings generated after committing an import plan.
public struct ConfigImportResult: Sendable {
    public var importedProfileCount: Int = 0
    public var skippedProfileCount: Int = 0
    public var updatedProfileCount: Int = 0
    public var importedGroupCount: Int = 0
    public var importedBookmarkCount: Int = 0
    public var warnings: [String] = []

    public init(
        importedProfileCount: Int = 0,
        skippedProfileCount: Int = 0,
        updatedProfileCount: Int = 0,
        importedGroupCount: Int = 0,
        importedBookmarkCount: Int = 0,
        warnings: [String] = []
    ) {
        self.importedProfileCount = importedProfileCount
        self.skippedProfileCount = skippedProfileCount
        self.updatedProfileCount = updatedProfileCount
        self.importedGroupCount = importedGroupCount
        self.importedBookmarkCount = importedBookmarkCount
        self.warnings = warnings
    }
}

/// High-performance importer for portable SparkleSFTP bundles and external client configs.
public enum ConfigImporter {
    /// Detects format from file data and optional filename hint.
    public static func detectFormat(data: Data, filename: String = "") -> ConfigSourceFormat {
        if let detected = detectFromMagicBytes(data) {
            return detected
        }
        if let detected = detectFromPrefixContent(data) {
            return detected
        }
        return detectFromFilenameExtension(filename)
    }

    private static func detectFromMagicBytes(_ data: Data) -> ConfigSourceFormat? {
        if data.count >= 9, data.prefix(9) == Data(SparkleVaultHeader.magicASCII.utf8) {
            return .sparkleVault
        }
        return nil
    }

    private static func detectFromPrefixContent(_ data: Data) -> ConfigSourceFormat? {
        guard let string = String(data: data.prefix(4096), encoding: .utf8) else {
            return nil
        }
        if string.contains("\"magic\": \"sparklesftp.config\"") ||
            string.contains("\"magic\":\"sparklesftp.config\"") {
            return .sparkleConfig
        }
        if string.contains(SparkleSFTPEncryptedArchive.formatIdentifier) {
            return .sparkleVault
        }
        if string.contains(SparkleSFTPConnectionExport.generatorIdentifier) ||
            string.contains("\"connections\":") {
            return .legacyExport
        }
        if string.contains("<FileZilla3>") || string.contains("<Servers>") {
            return .fileZillaXML
        }
        if string.contains("[Sessions]") || string.contains("[Configuration]") {
            return .winSCPINI
        }
        if string.hasPrefix("Host ") || string.contains("\nHost ") {
            return .openSSHConfig
        }
        return nil
    }

    private static func detectFromFilenameExtension(_ filename: String) -> ConfigSourceFormat {
        let lower = filename.lowercased()
        if lower.hasSuffix(".sparklevault") {
            return .sparkleVault
        }
        if lower.hasSuffix(".sparkleconfig") || lower.hasSuffix(".sparkleconfig.json") {
            return .sparkleConfig
        }
        if lower.hasSuffix(".xml") {
            return .fileZillaXML
        }
        if lower.hasSuffix(".ini") {
            return .winSCPINI
        }
        if lower == "config" || lower.hasSuffix("ssh_config") {
            return .openSSHConfig
        }
        return .unknown
    }
}
