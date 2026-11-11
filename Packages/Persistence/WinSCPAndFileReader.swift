import Foundation
import SparkleCore

/// Imports WinSCP `.ini` `[Sessions\...]` profiles cleanly.
public enum WinSCPIniImporter {
    public static func parse(iniContents: String) -> [ImportedConnection] {
        parseWithReport(iniContents: iniContents).connections
    }

    public static func parseWithReport(iniContents: String) -> ExternalImportReport {
        var results: [ImportedConnection] = []
        var skippedUnsupported = 0
        var currentSectionName: String?
        var currentFields: [String: String] = [:]

        for rawLine in iniContents.components(separatedBy: .newlines) {
            var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("\u{FEFF}") {
                line.removeFirst()
            }
            guard !line.isEmpty, !line.hasPrefix(";"), !line.hasPrefix("#") else { continue }
            if line.hasPrefix("["), line.hasSuffix("]") {
                let outcome = buildOutcome(section: currentSectionName, fields: currentFields)
                if let entry = outcome.connection {
                    results.append(entry)
                } else if outcome.unsupported {
                    skippedUnsupported += 1
                }
                currentSectionName = String(line.dropFirst().dropLast())
                currentFields = [:]
            } else if let eqIndex = line.firstIndex(of: "=") {
                let key = String(line[..<eqIndex]).trimmingCharacters(in: .whitespaces)
                let val = String(line[line.index(after: eqIndex)...]).trimmingCharacters(in: .whitespaces)
                currentFields[key] = val
            }
        }
        let tailOutcome = buildOutcome(section: currentSectionName, fields: currentFields)
        if let entry = tailOutcome.connection {
            results.append(entry)
        } else if tailOutcome.unsupported {
            skippedUnsupported += 1
        }

        return ExternalImportReport(
            format: .winSCPINI,
            connections: results,
            skippedUnsupported: skippedUnsupported
        )
    }

    private static func buildOutcome(
        section: String?,
        fields: [String: String]
    ) -> (connection: ImportedConnection?, unsupported: Bool) {
        guard let section,
              section.hasPrefix("Sessions\\"),
              let host = fields["HostName"],
              !host.isEmpty
        else {
            return (nil, false)
        }

        let rawSuffix = String(section.dropFirst("Sessions\\".count))
        let components = rawSuffix
            .split(separator: "\\", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        let sessionName = components.last ?? host
        let groupName = components.count > 1 ? components.dropLast().joined(separator: " / ") : nil

        guard let protocolType = resolveProtocol(
            fsProtocol: fields["FSProtocol"] ?? "0",
            ftpsMode: fields["Ftps"] ?? "0"
        ) else {
            return (nil, true)
        }

        let port = fields["PortNumber"].flatMap(Int.init) ?? protocolType.defaultPort
        let user = fields["UserName"]?.removingPercentEncoding ?? "root"
        let remoteDir = fields["RemoteDirectory"]?.removingPercentEncoding ?? "/"
        let localDir = fields["LocalDirectory"]?.removingPercentEncoding
        let hasKeyFile = !(fields["PublicKeyFile"]?.isEmpty ?? true)
        let authMethod: AuthMethod = hasKeyFile ? .publicKey : .password
        let hasEncryptedPass = !(fields["Password"]?.isEmpty ?? true)
        let proxy = parseProxy(fields: fields)

        let profile = ConnectionProfile(
            name: sessionName.isEmpty ? host : sessionName,
            protocolType: protocolType,
            host: host,
            port: port,
            username: user,
            authMethod: authMethod,
            proxy: proxy,
            defaultRemotePath: RemotePath(rawValue: remoteDir),
            defaultLocalPath: localDir
        )
        return (
            ImportedConnection(
                profile: profile,
                transientSecret: nil,
                groupName: groupName,
                secretStatus: hasEncryptedPass ? ImportedSecretStatus.encryptedUnavailable : ImportedSecretStatus.none,
                notes: fields["PublicKeyFile"].flatMap { $0.isEmpty ? nil : "Key: \($0)" }
            ),
            false
        )
    }

    private static func parseProxy(fields: [String: String]) -> ProxyConfiguration {
        let method = fields["ProxyMethod"] ?? "0"
        let host = fields["ProxyHost"]?.removingPercentEncoding ?? ""
        let port = fields["ProxyPort"].flatMap(Int.init) ?? 1080
        guard !host.isEmpty else { return ProxyConfiguration() }
        switch method {
        case "2": return ProxyConfiguration(kind: .socks5, host: host, port: port)
        case "3": return ProxyConfiguration(kind: .http, host: host, port: port)
        default: return ProxyConfiguration()
        }
    }

    private static func resolveProtocol(fsProtocol: String, ftpsMode: String) -> ProtocolType? {
        switch fsProtocol {
        case "0", "2":
            return .sftp
        case "1":
            return .scp
        case "5":
            switch ftpsMode {
            case "1": return .ftpsImplicit
            case "2", "3": return .ftpsExplicit
            default: return .ftp
            }
        case "6", "7":
            // WebDAV (6) and Amazon S3 (7) are outside SparkleSFTP's SFTP/SCP/FTP/FTPS scope.
            return nil
        default:
            return .sftp
        }
    }
}

/// Unified reader supporting security-scoped URLs and UTF-8 / UTF-16 BOM / Latin1 encodings.
public enum ExternalConnectionFileReader {
    public static func defaultFileZillaSiteFiles(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        let candidates = [
            homeDirectory.appendingPathComponent(".config/filezilla/sitemanager.xml"),
            homeDirectory.appendingPathComponent(".filezilla/sitemanager.xml"),
            homeDirectory.appendingPathComponent("Library/Preferences/FileZilla/sitemanager.xml")
        ]
        return candidates.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    public static func decodeText(from data: Data) -> String {
        if data.starts(with: [0xFF, 0xFE]),
           let utf16LE = String(bytes: Data(data.dropFirst(2)), encoding: .utf16LittleEndian) {
            return utf16LE
        }
        if data.starts(with: [0xFE, 0xFF]),
           let utf16BE = String(bytes: Data(data.dropFirst(2)), encoding: .utf16BigEndian) {
            return utf16BE
        }
        var utf8Data = data
        if utf8Data.starts(with: [0xEF, 0xBB, 0xBF]) {
            utf8Data = Data(utf8Data.dropFirst(3))
        }
        if let utf8 = String(bytes: utf8Data, encoding: .utf8) {
            return utf8
        }
        return String(bytes: data, encoding: .windowsCP1252)
            ?? String(bytes: data, encoding: .isoLatin1)
            ?? ""
    }

    public static func inspect(url: URL) throws -> ExternalImportReport {
        let didScope = url.startAccessingSecurityScopedResource()
        defer {
            if didScope {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let data = try Data(contentsOf: url)
        return try inspect(data: data, fileExtension: url.pathExtension.lowercased())
    }

    public static func inspect(data: Data, fileExtension: String) throws -> ExternalImportReport {
        let text = decodeText(from: data)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if fileExtension == "xml" || trimmed.hasPrefix("<") {
            return try FileZillaImporter.parseWithReport(xmlData: data)
        }
        return WinSCPIniImporter.parseWithReport(iniContents: text)
    }
}
