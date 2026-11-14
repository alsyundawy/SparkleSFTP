import Foundation
import SparkleCore

/// High-level exporter for portable SparkleSFTP configuration bundles and external FileZilla XML.
public enum ConfigExporter {
    /// Builds a full or scoped `SparkleConfigBundle` from application state components.
    public static func createBundle(
        scope: ConfigExportScope = .all,
        profiles: [ConnectionProfile] = [],
        groups: [ServerGroup] = [],
        bookmarks: [BookmarkItem] = [],
        pathHistory: [PathHistoryItem] = [],
        snippets: [CommandSnippet] = [],
        portForwardingRules: [PortForwardingRule] = [],
        settings: [String: String] = [:],
        customThemes: [SparkleCustomThemeExport] = []
    ) throws -> SparkleConfigBundle {
        let payload = ConfigBundlePayload(
            profiles: scope.contains(.profiles) ? profiles : [],
            groups: scope.contains(.groups) ? groups : [],
            bookmarks: scope.contains(.bookmarks) ? bookmarks : [],
            pathHistory: scope.contains(.pathHistory) ? pathHistory : [],
            snippets: scope.contains(.snippets) ? snippets : [],
            portForwardingRules: scope.contains(.portForwarding) ? portForwardingRules : [],
            settings: scope.contains(.settings) ? settings : [:],
            customThemes: scope.contains(.customThemes) ? customThemes : []
        )

        let integrity = try ConfigBundleCrypto.computeIntegrity(payload: payload)

        return SparkleConfigBundle(
            magic: SparkleConfigBundle.currentMagic,
            schemaVersion: SparkleConfigBundle.currentSchemaVersion,
            kind: scope == .all ? "full" : "partial",
            appVersion: SparkleConfigBundle.currentAppVersion,
            createdAt: Date(),
            payload: payload,
            integrity: integrity
        )
    }

    /// Exports bundle to disk at destination URL with optional vault passphrase encryption.
    public static func exportToFile(
        bundle: SparkleConfigBundle,
        destinationURL: URL,
        passphrase: String? = nil
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(bundle)

        if let passphrase, !passphrase.isEmpty {
            // Format B: Encrypted Binary Vault
            let vaultData = try ConfigBundleCrypto.encryptVault(bundleData: jsonData, passphrase: passphrase)
            try writeSecureAtomic(data: vaultData, to: destinationURL)
        } else {
            // Format A: Plaintext JSON Bundle
            try writeSecureAtomic(data: jsonData, to: destinationURL)
        }
    }

    /// Atomically writes data with strict POSIX 0600 file permissions (CWE-732).
    private static func writeSecureAtomic(data: Data, to url: URL) throws {
        let tempURL = url.deletingLastPathComponent().appendingPathComponent(".tmp.\(UUID().uuidString)")
        try data.write(to: tempURL, options: .atomic)
        // Set POSIX permissions 0600 (read/write for owner only)
        let permissions: [FileAttributeKey: Any] = [.posixPermissions: 0o600]
        try? FileManager.default.setAttributes(permissions, ofItemAtPath: tempURL.path)
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try? FileManager.default.removeItem(at: url)
        }
        try FileManager.default.moveItem(at: tempURL, to: url)
    }

    /// Exports connection profiles and groups to FileZilla 3 `sitemanager.xml` format.
    public static func exportToFileZillaXML(
        profiles: [ConnectionProfile],
        groups: [ServerGroup] = []
    ) -> String {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        xml += "<FileZilla3 version=\"3.0.0\" platform=\"Mac\">\n"
        xml += "  <Servers>\n"

        // Group mapping
        var groupMap: [UUID: String] = [:]
        for group in groups {
            groupMap[group.id] = group.name
        }

        for profile in profiles {
            let protocolNum = switch profile.protocolType {
            case .ftp: 0
            case .sftp, .scp: 1
            case .ftpsExplicit, .ftpsImplicit: 4
            }

            let escapedName = escapeXML(profile.name)
            let escapedHost = escapeXML(profile.host)
            let escapedUser = escapeXML(profile.username)
            let groupName = profile.groupID.flatMap { groupMap[$0] } ?? "SparkleSFTP"

            xml += "    <Server>\n"
            xml += "      <Host>\(escapedHost)</Host>\n"
            xml += "      <Port>\(profile.port)</Port>\n"
            xml += "      <Protocol>\(protocolNum)</Protocol>\n"
            xml += "      <Type>0</Type>\n"
            xml += "      <User>\(escapedUser)</User>\n"
            xml += "      <Logontype>1</Logontype>\n" // Ask for password (sanitized, zero plaintext secret leakage)
            xml += "      <Name>\(escapedName)</Name>\n"
            xml += "      <Group>\(escapeXML(groupName))</Group>\n"
            xml += "    </Server>\n"
        }

        xml += "  </Servers>\n"
        xml += "</FileZilla3>\n"
        return xml
    }

    private static func escapeXML(_ str: String) -> String {
        str.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
