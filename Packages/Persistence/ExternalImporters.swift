import Foundation
import SparkleCore

public struct ImportedConnection: Sendable, Equatable {
    public let profile: ConnectionProfile
    /// Transient secret data decoded during import; caller must save into KeychainService and discard.
    public let transientSecret: Data?

    public init(profile: ConnectionProfile, transientSecret: Data? = nil) {
        self.profile = profile
        self.transientSecret = transientSecret
    }
}

/// Imports FileZilla `sitemanager.xml` server entries safely without persisting secrets to JSON.
public enum FileZillaImporter {
    public static func parse(xmlData: Data) throws -> [ImportedConnection] {
        let delegate = FileZillaXMLDelegate()
        let parser = XMLParser(data: xmlData)
        parser.delegate = delegate
        guard parser.parse() else {
            throw AppError.persistenceFailure(
                reason: parser.parserError?.localizedDescription ?? "Malformed FileZilla XML"
            )
        }
        return delegate.results
    }
}

private final class FileZillaXMLDelegate: NSObject, XMLParserDelegate {
    var results: [ImportedConnection] = []
    private var inServer = false
    private var currentElement = ""
    private var buffer = ""
    private var fields: [String: String] = [:]

    func parser(
        _: XMLParser,
        didStartElement elementName: String,
        namespaceURI _: String?,
        qualifiedName _: String?,
        attributes _: [String: String] = [:]
    ) {
        currentElement = elementName
        buffer = ""
        if elementName == "Server" {
            inServer = true
            fields = [:]
        }
    }

    func parser(_: XMLParser, foundCharacters string: String) {
        if inServer {
            buffer.append(string)
        }
    }

    func parser(
        _: XMLParser,
        didEndElement elementName: String,
        namespaceURI _: String?,
        qualifiedName _: String?
    ) {
        guard inServer else { return }
        if elementName == "Server" {
            if let imported = buildConnection(from: fields) {
                results.append(imported)
            }
            inServer = false
            fields = [:]
            return
        }
        if elementName == currentElement {
            fields[elementName] = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func buildConnection(from dict: [String: String]) -> ImportedConnection? {
        guard let host = dict["Host"], !host.isEmpty else { return nil }
        let protoCode = dict["Protocol"] ?? "0"
        let protocolType: ProtocolType = switch protoCode {
        case "1": .sftp
        case "3": .ftpsImplicit
        case "4": .ftpsExplicit
        default: .ftp
        }
        let port = dict["Port"].flatMap(Int.init) ?? protocolType.defaultPort
        let user = dict["User"] ?? "anonymous"
        let name = (dict["Name"].flatMap { $0.isEmpty ? nil : $0 }) ?? host
        let remoteDir = dict["RemoteDir"].flatMap { decodeFileZillaRemoteDir($0) } ?? "/"
        let localDir = dict["LocalDir"]
        let logonType = dict["Logontype"] ?? "1"
        let authMethod: AuthMethod = (logonType == "0") ? .anonymous : (logonType == "5" ? .publicKey : .password)

        let secretData: Data? = if let pass = dict["Pass"], !pass.isEmpty {
            Data(base64Encoded: pass) ?? pass.data(using: .utf8)
        } else {
            nil
        }

        let passwordRef = secretData != nil ? SecretReference(kind: .password) : nil
        let profile = ConnectionProfile(
            name: name,
            protocolType: protocolType,
            host: host,
            port: port,
            username: user,
            authMethod: authMethod,
            passwordRef: passwordRef,
            defaultRemotePath: RemotePath(rawValue: remoteDir),
            defaultLocalPath: localDir
        )
        return ImportedConnection(profile: profile, transientSecret: secretData)
    }

    private func decodeFileZillaRemoteDir(_ raw: String) -> String? {
        // FileZilla formats remote paths like "1 0 3 var 3 www"
        let parts = raw.split(separator: " ")
        guard parts.count >= 2 else { return raw.hasPrefix("/") ? raw : nil }
        var segments: [String] = []
        var idx = 2
        while idx + 1 < parts.count {
            segments.append(String(parts[idx + 1]))
            idx += 2
        }
        return segments.isEmpty ? "/" : "/" + segments.joined(separator: "/")
    }
}

/// Imports WinSCP `.ini` `[Sessions\...]` profiles cleanly.
public enum WinSCPIniImporter {
    public static func parse(iniContents: String) -> [ImportedConnection] {
        var results: [ImportedConnection] = []
        var currentSectionName: String?
        var currentFields: [String: String] = [:]

        for rawLine in iniContents.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix(";"), !line.hasPrefix("#") else { continue }
            if line.hasPrefix("["), line.hasSuffix("]") {
                if let entry = buildConnection(section: currentSectionName, fields: currentFields) {
                    results.append(entry)
                }
                currentSectionName = String(line.dropFirst().dropLast())
                currentFields = [:]
            } else if let eqIndex = line.firstIndex(of: "=") {
                let key = String(line[..<eqIndex]).trimmingCharacters(in: .whitespaces)
                let val = String(line[line.index(after: eqIndex)...]).trimmingCharacters(in: .whitespaces)
                currentFields[key] = val
            }
        }
        if let entry = buildConnection(section: currentSectionName, fields: currentFields) {
            results.append(entry)
        }
        return results
    }

    private static func buildConnection(
        section: String?,
        fields: [String: String]
    ) -> ImportedConnection? {
        guard let section,
              section.hasPrefix("Sessions\\"),
              let host = fields["HostName"],
              !host.isEmpty
        else {
            return nil
        }

        let rawSuffix = String(section.dropFirst("Sessions\\".count))
        let rawName = rawSuffix.removingPercentEncoding ?? rawSuffix
        let protocolType = resolveProtocol(
            fsProtocol: fields["FSProtocol"] ?? "0",
            ftpsMode: fields["Ftps"] ?? "0"
        )
        let port = fields["PortNumber"].flatMap(Int.init) ?? protocolType.defaultPort
        let user = fields["UserName"]?.removingPercentEncoding ?? "root"
        let remoteDir = fields["RemoteDirectory"]?.removingPercentEncoding ?? "/"
        let localDir = fields["LocalDirectory"]?.removingPercentEncoding

        let profile = ConnectionProfile(
            name: rawName.isEmpty ? host : rawName,
            protocolType: protocolType,
            host: host,
            port: port,
            username: user,
            authMethod: .password,
            defaultRemotePath: RemotePath(rawValue: remoteDir),
            defaultLocalPath: localDir
        )
        return ImportedConnection(profile: profile, transientSecret: nil)
    }

    private static func resolveProtocol(fsProtocol: String, ftpsMode: String) -> ProtocolType {
        switch fsProtocol {
        case "1":
            return .scp
        case "5":
            switch ftpsMode {
            case "1": return .ftpsImplicit
            case "2", "3": return .ftpsExplicit
            default: return .ftp
            }
        default:
            return .sftp
        }
    }
}
