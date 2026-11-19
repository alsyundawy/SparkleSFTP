import Foundation
import SparkleCore

/// Represents a single hop in an OpenSSH ProxyJump chain (Task 2.5).
public struct ProxyJumpHop: Sendable, Codable, Hashable, Equatable {
    public let user: String?
    public let host: String
    public let port: Int

    public init(user: String? = nil, host: String, port: Int = 22) {
        self.user = user
        self.host = host
        self.port = port
    }

    public var directiveString: String {
        let hostPart = host.contains(":") ? "[\(host)]" : host
        let portPart = port == 22 ? "" : ":\(port)"
        if let user, !user.isEmpty {
            return "\(user)@\(hostPart)\(portPart)"
        }
        return "\(hostPart)\(portPart)"
    }
}

/// Robust OpenSSH ProxyJump syntax parser validating multi-hop bastion topologies (Task 2.5, CWE-78).
public enum ProxyJumpParser {
    private static let dangerousCharacters = CharacterSet(charactersIn: ";|&$`\n\r\t \0\\\"'")

    /// Parses an OpenSSH ProxyJump directive string into validated sequential hops.
    /// Example: "jumpbox1:22,bastion@jumpbox2:2222,[::1]:2222"
    public static func parse(directive: String) throws -> [ProxyJumpHop] {
        let trimmed = directive.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.lowercased() != "none" else {
            return []
        }

        let segments = trimmed.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        var hops: [ProxyJumpHop] = []

        for segment in segments where !segment.isEmpty {
            let hop = try parseSingleHop(String(segment))
            hops.append(hop)
        }

        return hops
    }

    private static func parseSingleHop(_ segment: String) throws -> ProxyJumpHop {
        guard segment.rangeOfCharacter(from: dangerousCharacters) == nil else {
            throw AppError.invalidConfiguration("ProxyJump hop contains illegal characters: \(segment)")
        }

        var remaining = segment
        var user: String?

        if let atIndex = remaining.firstIndex(of: "@") {
            let userPart = String(remaining[..<atIndex])
            guard !userPart.isEmpty else {
                throw AppError.invalidConfiguration("Empty username in ProxyJump hop: \(segment)")
            }
            user = userPart
            remaining = String(remaining[remaining.index(after: atIndex)...])
        }

        let (host, port) = try extractHostAndPort(from: remaining, segment: segment)
        guard !host.isEmpty else {
            throw AppError.invalidConfiguration("Empty host in ProxyJump hop: \(segment)")
        }

        return ProxyJumpHop(user: user, host: host, port: port)
    }

    private static func extractHostAndPort(from target: String, segment: String) throws -> (host: String, port: Int) {
        if target.hasPrefix("[") {
            return try parseBracketedIPv6(target, segment: segment)
        }
        if let colonIndex = target.lastIndex(of: ":") {
            let portStr = String(target[target.index(after: colonIndex)...])
            guard let parsedPort = Int(portStr), (1...65535).contains(parsedPort) else {
                throw AppError.invalidConfiguration("Invalid port in ProxyJump hop: \(segment)")
            }
            return (String(target[..<colonIndex]), parsedPort)
        }
        return (target, 22)
    }

    private static func parseBracketedIPv6(_ target: String, segment: String) throws -> (host: String, port: Int) {
        guard let closingBracket = target.firstIndex(of: "]") else {
            throw AppError.invalidConfiguration("Mismatched IPv6 bracket in ProxyJump hop: \(segment)")
        }
        let host = String(target[target.index(after: target.startIndex)..<closingBracket])
        let afterBracket = target[target.index(after: closingBracket)...]
        var port = 22
        if afterBracket.hasPrefix(":") {
            let portStr = String(afterBracket.dropFirst())
            guard let parsedPort = Int(portStr), (1...65535).contains(parsedPort) else {
                throw AppError.invalidConfiguration("Invalid port in ProxyJump hop: \(segment)")
            }
            port = parsedPort
        } else if !afterBracket.isEmpty {
            throw AppError.invalidConfiguration("Malformed IPv6 ProxyJump hop: \(segment)")
        }
        return (host, port)
    }
}
