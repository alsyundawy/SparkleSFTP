import Foundation
import SparkleCore

public enum ExternalImportFormat: String, Sendable, Codable, Equatable {
    case fileZillaXML
    case winSCPINI
}

public enum ImportedSecretStatus: String, Sendable, Codable, Equatable {
    case none
    case plaintextReady
    case encryptedUnavailable
}

public struct ImportedConnection: Sendable, Equatable {
    public let profile: ConnectionProfile
    /// Transient secret data decoded during import; caller must save into KeychainService and discard.
    public let transientSecret: Data?
    public let groupName: String?
    public let secretStatus: ImportedSecretStatus
    public let notes: String?

    public init(
        profile: ConnectionProfile,
        transientSecret: Data? = nil,
        groupName: String? = nil,
        secretStatus: ImportedSecretStatus? = nil,
        notes: String? = nil
    ) {
        self.profile = profile
        self.transientSecret = transientSecret
        self.groupName = groupName
        self.secretStatus = secretStatus ?? (transientSecret != nil ? .plaintextReady : .none)
        self.notes = notes
    }
}

public struct ExternalImportReport: Sendable, Equatable {
    public let format: ExternalImportFormat
    public let connections: [ImportedConnection]
    public let skippedUnsupported: Int
    public let warnings: [String]

    public init(
        format: ExternalImportFormat,
        connections: [ImportedConnection],
        skippedUnsupported: Int = 0,
        warnings: [String] = []
    ) {
        self.format = format
        self.connections = connections
        self.skippedUnsupported = skippedUnsupported
        self.warnings = warnings
    }
}

/// Imports FileZilla `sitemanager.xml` server entries safely without persisting secrets to JSON.
public enum FileZillaImporter {
    public static func parse(xmlData: Data) throws -> [ImportedConnection] {
        try parseWithReport(xmlData: xmlData).connections
    }

    public static func parseWithReport(xmlData: Data) throws -> ExternalImportReport {
        let delegate = FileZillaXMLDelegate()
        let parser = XMLParser(data: xmlData)
        parser.delegate = delegate
        guard parser.parse() else {
            throw AppError.persistenceFailure(
                reason: parser.parserError?.localizedDescription ?? "Malformed FileZilla XML"
            )
        }
        return ExternalImportReport(
            format: .fileZillaXML,
            connections: delegate.results,
            skippedUnsupported: delegate.skippedUnsupported,
            warnings: delegate.warnings
        )
    }
}

private final class FileZillaXMLDelegate: NSObject, XMLParserDelegate {
    var results: [ImportedConnection] = []
    var skippedUnsupported = 0
    var warnings: [String] = []
    private var inServer = false
    private var currentElement = ""
    private var buffer = ""
    private var fields: [String: String] = [:]
    private var passEncoding: String?
    private var folderStack: [String] = []
    private var readingFolderName = false
    private var folderDepthAdded: [Bool] = []

    func parser(
        _: XMLParser,
        didStartElement elementName: String,
        namespaceURI _: String?,
        qualifiedName _: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if readingFolderName, elementName != "Name" {
            flushPendingFolderName()
        }
        currentElement = elementName
        buffer = ""
        if elementName == "Folder" {
            folderDepthAdded.append(false)
            readingFolderName = !inServer
        } else if elementName == "Server" {
            inServer = true
            readingFolderName = false
            fields = [:]
            passEncoding = nil
        } else if inServer, elementName == "Pass" {
            passEncoding = attributeDict["encoding"]?.lowercased()
        }
    }

    func parser(_: XMLParser, foundCharacters string: String) {
        if inServer || readingFolderName {
            buffer.append(string)
        }
    }

    func parser(
        _: XMLParser,
        didEndElement elementName: String,
        namespaceURI _: String?,
        qualifiedName _: String?
    ) {
        if elementName == "Folder" {
            flushPendingFolderName()
            if let didPush = folderDepthAdded.popLast(), didPush, !folderStack.isEmpty {
                folderStack.removeLast()
            }
            return
        }

        if readingFolderName, elementName == "Name" {
            flushPendingFolderName()
            return
        }

        guard inServer else { return }
        if elementName == "Server" {
            if let imported = buildConnection(from: fields, passEncoding: passEncoding) {
                results.append(imported)
            } else {
                skippedUnsupported += 1
            }
            inServer = false
            fields = [:]
            passEncoding = nil
            return
        }
        if elementName == currentElement {
            fields[elementName] = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func flushPendingFolderName() {
        guard readingFolderName, let lastIdx = folderDepthAdded.indices.last else { return }
        let folderName = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !folderName.isEmpty, !folderDepthAdded[lastIdx] {
            folderStack.append(folderName)
            folderDepthAdded[lastIdx] = true
        }
        readingFolderName = false
        buffer = ""
    }

    private func buildConnection(
        from dict: [String: String],
        passEncoding: String?
    ) -> ImportedConnection? {
        guard let host = dict["Host"], !host.isEmpty else { return nil }
        let protoCode = dict["Protocol"] ?? "0"
        let protocolType: ProtocolType
        switch protoCode {
        case "1": protocolType = .sftp
        case "3": protocolType = .ftpsImplicit
        case "2", "4", "6": protocolType = .ftpsExplicit
        case "0": protocolType = .ftp
        default: return nil
        }

        let port = dict["Port"].flatMap(Int.init) ?? protocolType.defaultPort
        let user = (dict["User"].flatMap { $0.isEmpty ? nil : $0 }) ?? "anonymous"
        let name = (dict["Name"].flatMap { $0.isEmpty ? nil : $0 }) ?? host
        let remoteDir = dict["RemoteDir"].flatMap { decodeFileZillaRemoteDir($0) } ?? "/"
        let localDir = dict["LocalDir"].flatMap { $0.isEmpty ? nil : $0 }
        let logonType = dict["Logontype"] ?? "1"
        let authMethod: AuthMethod = switch logonType {
        case "0": .anonymous
        case "2", "3": .keyboardInteractive
        case "4", "5": .publicKey
        default: .password
        }

        let decodedSecret = decodePassword(rawPass: dict["Pass"], encoding: passEncoding)
        let passwordRef = decodedSecret.data != nil ? SecretReference(kind: .password) : nil
        let groupName = folderStack.isEmpty ? nil : folderStack.joined(separator: " / ")
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
        return ImportedConnection(
            profile: profile,
            transientSecret: decodedSecret.data,
            groupName: groupName,
            secretStatus: decodedSecret.status,
            notes: dict["Comments"]
        )
    }

    private func decodePassword(
        rawPass: String?,
        encoding: String?
    ) -> (data: Data?, status: ImportedSecretStatus) {
        guard let pass = rawPass, !pass.isEmpty else {
            return (nil, .none)
        }
        if encoding == "crypt" {
            return (nil, .encryptedUnavailable)
        }
        if encoding == "base64", let decoded = Data(base64Encoded: pass) {
            return (decoded, .plaintextReady)
        }
        return (pass.data(using: .utf8), .plaintextReady)
    }

    private func decodeFileZillaRemoteDir(_ raw: String) -> String? {
        // FileZilla encodes remote paths like "1 0 3 var 3 www"
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
