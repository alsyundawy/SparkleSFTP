import Foundation
import SparkleCore

public struct SSHConfigHostEntry: Sendable, Equatable {
    public let alias: String
    public var hostName: String?
    public var port: Int?
    public var user: String?
    public var identityFile: String?
    public var proxyJump: String?

    public init(
        alias: String,
        hostName: String? = nil,
        port: Int? = nil,
        user: String? = nil,
        identityFile: String? = nil,
        proxyJump: String? = nil
    ) {
        self.alias = alias
        self.hostName = hostName
        self.port = port
        self.user = user
        self.identityFile = identityFile
        self.proxyJump = proxyJump
    }

    public func toConnectionProfile() -> ConnectionProfile {
        let resolvedHost = hostName ?? alias
        let resolvedUser = user ?? NSUserName()
        let authMethod: AuthMethod = identityFile != nil ? .publicKey : .password
        return ConnectionProfile(
            name: alias,
            protocolType: .sftp,
            host: resolvedHost,
            port: port ?? 22,
            username: resolvedUser,
            authMethod: authMethod
        )
    }
}

private struct SSHConfigAccumulator {
    var aliases: [String] = []
    var hostName: String?
    var port: Int?
    var user: String?
    var identityFile: String?
    var proxyJump: String?

    func materializedEntries() -> [SSHConfigHostEntry] {
        aliases
            .filter { !$0.contains("*") && !$0.contains("?") }
            .map {
                SSHConfigHostEntry(
                    alias: $0,
                    hostName: hostName,
                    port: port,
                    user: user,
                    identityFile: identityFile,
                    proxyJump: proxyJump
                )
            }
    }

    mutating func reset(aliases: [String]) {
        self = SSHConfigAccumulator(aliases: aliases)
    }

    mutating func apply(keyword: String, value: String, homeDirectory: URL) {
        switch keyword {
        case "hostname":
            hostName = value
        case "port":
            port = Int(value)
        case "user":
            user = value
        case "identityfile":
            identityFile = value.hasPrefix("~/")
                ? homeDirectory.path + String(value.dropFirst())
                : value
        case "proxyjump":
            proxyJump = value
        default:
            break
        }
    }
}

/// Parses OpenSSH client configuration files (`~/.ssh/config`).
public enum SSHConfigParser {
    public static func parse(
        contents: String,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [SSHConfigHostEntry] {
        var entries: [SSHConfigHostEntry] = []
        var accumulator = SSHConfigAccumulator()

        for rawLine in contents.components(separatedBy: .newlines) {
            guard let (keyword, value) = parseDirective(rawLine) else { continue }
            if keyword == "host" {
                entries.append(contentsOf: accumulator.materializedEntries())
                let aliases = value.split(whereSeparator: { $0.isWhitespace }).map(String.init)
                accumulator.reset(aliases: aliases)
            } else {
                accumulator.apply(keyword: keyword, value: value, homeDirectory: homeDirectory)
            }
        }

        entries.append(contentsOf: accumulator.materializedEntries())
        return entries
    }

    private static func parseDirective(_ rawLine: String) -> (String, String)? {
        let stripped = stripInlineComment(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty else { return nil }
        let parts = stripped.split(maxSplits: 1, omittingEmptySubsequences: true) {
            $0 == " " || $0 == "\t" || $0 == "="
        }
        guard parts.count == 2 else { return nil }
        let keyword = parts[0].lowercased()
        let value = parts[1]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        return (keyword, value)
    }

    private static func stripInlineComment(_ line: String) -> String {
        if let hashIndex = line.firstIndex(of: "#") {
            return String(line[..<hashIndex])
        }
        return line
    }
}
