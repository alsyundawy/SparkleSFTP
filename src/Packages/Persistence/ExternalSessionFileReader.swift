import Foundation
import SparkleCore

private struct IniSessionSection {
    let name: String
    let fields: [String: String]
}

private enum IniSessionPasswordDecoder {
    private static let magic: UInt8 = 0xA3
    private static let versionFlag: UInt8 = 0xFF
    private static let internalMarker: UInt8 = 0x00

    static func decrypt(
        encodedHex: String?,
        candidateKeys: [Data],
        vaultPassEnabled: Bool
    ) -> (data: Data?, status: ImportedSecretStatus) {
        guard let rawHex = encodedHex?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawHex.isEmpty
        else {
            return (nil, .none)
        }
        guard !vaultPassEnabled, let rawBytes = parseHexBytes(rawHex), !rawBytes.isEmpty else {
            return (nil, .encryptedUnavailable)
        }

        let flag = decodeByte(rawBytes[0])
        if flag == versionFlag {
            return decryptStandard(bytes: rawBytes, candidateKeys: candidateKeys)
        }
        return decryptLegacy(bytes: rawBytes, rawLength: Int(flag))
    }

    private static func decryptStandard(
        bytes: [UInt8],
        candidateKeys: [Data]
    ) -> (data: Data?, status: ImportedSecretStatus) {
        guard bytes.count >= 4, decodeByte(bytes[1]) == internalMarker else {
            return (nil, .encryptedUnavailable)
        }
        let length = Int(decodeByte(bytes[2]))
        let shift = Int(decodeByte(bytes[3]))
        let start = 4 + shift
        guard start <= bytes.count, length <= bytes.count - start else {
            return (nil, .encryptedUnavailable)
        }

        let plainBytes = (start ..< (start + length)).map { decodeByte(bytes[$0]) }
        let plainData = Data(plainBytes)
        for keyData in candidateKeys where !keyData.isEmpty && plainData.starts(with: keyData) {
            let trimmed = Data(plainData.dropFirst(keyData.count))
            guard String(data: trimmed, encoding: .utf8) != nil else {
                return (nil, .encryptedUnavailable)
            }
            return (trimmed, .plaintextReady)
        }
        return (nil, .encryptedUnavailable)
    }

    private static func decryptLegacy(
        bytes: [UInt8],
        rawLength: Int
    ) -> (data: Data?, status: ImportedSecretStatus) {
        guard bytes.count >= 2, rawLength <= 64 else {
            return (nil, .encryptedUnavailable)
        }
        let shift = Int(decodeByte(bytes[1]))
        let start = 2 + shift
        guard start <= bytes.count, rawLength <= bytes.count - start else {
            return (nil, .encryptedUnavailable)
        }

        let plainBytes = (start ..< (start + rawLength)).map { decodeByte(bytes[$0]) }
        guard !plainBytes.contains(where: { $0 < 0x20 || $0 == 0x7F }),
              String(data: Data(plainBytes), encoding: .utf8) != nil
        else {
            return (nil, .encryptedUnavailable)
        }
        return (Data(plainBytes), .plaintextReady)
    }

    private static func decodeByte(_ value: UInt8) -> UInt8 {
        ~(value ^ magic)
    }

    private static func parseHexBytes(_ hex: String) -> [UInt8]? {
        let chars = Array(hex.utf8)
        guard chars.count.isMultiple(of: 2) else { return nil }
        var output: [UInt8] = []
        output.reserveCapacity(chars.count / 2)
        var idx = 0
        while idx < chars.count {
            guard let high = hexNibble(chars[idx]), let low = hexNibble(chars[idx + 1]) else {
                return nil
            }
            output.append((high << 4) | low)
            idx += 2
        }
        return output
    }

    private static func hexNibble(_ ascii: UInt8) -> UInt8? {
        switch ascii {
        case 0x30 ... 0x39: ascii - 0x30
        case 0x41 ... 0x46: ascii - 0x41 + 10
        case 0x61 ... 0x66: ascii - 0x61 + 10
        default: nil
        }
    }
}

/// Imports Commander `.ini` `[Sessions\...]` profiles cleanly, including `0xA3` simple password decoding.
public enum IniSessionImporter {
    public static func parse(iniContents: String) -> [ImportedConnection] {
        parseWithReport(iniContents: iniContents).connections
    }

    public static func parseWithReport(iniContents: String) -> ExternalImportReport {
        let parsed = parseSections(from: iniContents)
        var results: [ImportedConnection] = []
        var skippedUnsupported = 0

        for section in parsed.sections {
            let outcome = buildOutcome(
                section: section.name,
                fields: section.fields,
                vaultPassEnabled: parsed.vaultPassEnabled
            )
            if let entry = outcome.connection {
                results.append(entry)
            } else if outcome.unsupported {
                skippedUnsupported += 1
            }
        }

        return ExternalImportReport(
            format: .commanderINI,
            connections: results,
            skippedUnsupported: skippedUnsupported
        )
    }

    private static func parseSections(from iniContents: String) -> (
        sections: [IniSessionSection],
        vaultPassEnabled: Bool
    ) {
        var sections: [IniSessionSection] = []
        var currentName: String?
        var currentFields: [String: String] = [:]
        var vaultPassEnabled = false

        for rawLine in iniContents.components(separatedBy: .newlines) {
            var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("\u{FEFF}") {
                line.removeFirst()
            }
            guard !line.isEmpty, !line.hasPrefix(";"), !line.hasPrefix("#") else { continue }
            if line.hasPrefix("["), line.hasSuffix("]") {
                commitSection(
                    name: currentName,
                    fields: currentFields,
                    sections: &sections,
                    vaultPassEnabled: &vaultPassEnabled
                )
                currentName = String(line.dropFirst().dropLast())
                currentFields = [:]
            } else if let eqIndex = line.firstIndex(of: "=") {
                let key = String(line[..<eqIndex]).trimmingCharacters(in: .whitespaces)
                let val = String(line[line.index(after: eqIndex)...]).trimmingCharacters(in: .whitespaces)
                currentFields[key] = val
            }
        }
        commitSection(
            name: currentName,
            fields: currentFields,
            sections: &sections,
            vaultPassEnabled: &vaultPassEnabled
        )
        return (sections, vaultPassEnabled)
    }

    private static func commitSection(
        name: String?,
        fields: [String: String],
        sections: inout [IniSessionSection],
        vaultPassEnabled: inout Bool
    ) {
        guard let name else { return }
        if name.caseInsensitiveCompare("Configuration\\Security") == .orderedSame,
           fields["UseMasterPassword"] == "1" {
            vaultPassEnabled = true
        }
        sections.append(IniSessionSection(name: name, fields: fields))
    }

    private static func buildOutcome(
        section: String,
        fields: [String: String],
        vaultPassEnabled: Bool
    ) -> (connection: ImportedConnection?, unsupported: Bool) {
        guard section.hasPrefix("Sessions\\"),
              let rawHost = fields["HostName"],
              !rawHost.isEmpty
        else {
            return (nil, false)
        }
        let host = rawHost.removingPercentEncoding ?? rawHost
        let identity = resolveSessionNameAndGroup(section: section, host: host)
        guard let protocolType = resolveProtocol(
            fsProtocol: fields["FSProtocol"] ?? "0",
            ftpsMode: fields["Ftps"] ?? "0"
        ) else {
            return (nil, true)
        }

        let rawUser = fields["UserName"] ?? ""
        let decodedUser = rawUser.removingPercentEncoding ?? rawUser
        let user = decodedUser.isEmpty ? "root" : decodedUser
        let secret = decryptSessionSecret(
            fields: fields,
            rawHost: rawHost,
            host: host,
            vaultPassEnabled: vaultPassEnabled
        )
        let profile = ConnectionProfile(
            name: identity.name,
            protocolType: protocolType,
            host: host,
            port: fields["PortNumber"].flatMap(Int.init) ?? protocolType.defaultPort,
            username: user,
            authMethod: (fields["PublicKeyFile"]?.isEmpty ?? true) ? .password : .publicKey,
            passwordRef: secret.data != nil ? SecretReference(kind: .password) : nil,
            proxy: parseProxy(fields: fields),
            defaultRemotePath: RemotePath(rawValue: fields["RemoteDirectory"]?.removingPercentEncoding ?? "/"),
            defaultLocalPath: fields["LocalDirectory"]?.removingPercentEncoding
        )
        return (
            ImportedConnection(
                profile: profile,
                transientSecret: secret.data,
                groupName: identity.group,
                secretStatus: secret.status,
                notes: fields["PublicKeyFile"].flatMap { $0.isEmpty ? nil : "Key: \($0)" }
            ),
            false
        )
    }

    private static func resolveSessionNameAndGroup(
        section: String,
        host: String
    ) -> (name: String, group: String?) {
        let rawSuffix = String(section.dropFirst("Sessions\\".count))
        let components = rawSuffix
            .split(separator: "\\", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        let sessionName = components.last ?? host
        let groupName = components.count > 1 ? components.dropLast().joined(separator: " / ") : nil
        return (sessionName.isEmpty ? host : sessionName, groupName)
    }

    private static func decryptSessionSecret(
        fields: [String: String],
        rawHost: String,
        host: String,
        vaultPassEnabled: Bool
    ) -> (data: Data?, status: ImportedSecretStatus) {
        let rawUser = fields["UserName"] ?? ""
        let decodedUser = rawUser.removingPercentEncoding ?? rawUser
        let candidateKeys = buildKeyCandidates(
            rawUser: rawUser,
            decodedUser: decodedUser,
            rawHost: rawHost,
            host: host
        )
        return IniSessionPasswordDecoder.decrypt(
            encodedHex: fields["Password"],
            candidateKeys: candidateKeys,
            vaultPassEnabled: vaultPassEnabled
        )
    }

    private static func buildKeyCandidates(
        rawUser: String,
        decodedUser: String,
        rawHost: String,
        host: String
    ) -> [Data] {
        let candidates = [
            decodedUser + host,
            rawUser + rawHost,
            decodedUser + rawHost,
            rawUser + host
        ]
        var unique: [Data] = []
        for candidate in candidates {
            let encoded = Data(candidate.utf8)
            if !unique.contains(encoded) {
                unique.append(encoded)
            }
        }
        return unique
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
        case "0":
            return .scp
        case "1", "2":
            return .sftp
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
