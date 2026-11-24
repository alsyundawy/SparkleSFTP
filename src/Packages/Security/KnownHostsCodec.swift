import Crypto
import Foundation
import SparkleCore

/// Encodes and decodes standard OpenSSH `known_hosts` format supporting both plain
/// and HMAC-SHA1 hashed host specifications (`|1|salt|hash`).
public enum KnownHostsCodec {
    public struct KnownHostLine: Sendable, Equatable {
        public let hostPattern: String
        public let keyType: String
        public let rawKeyData: Data
        public let comment: String?

        public init(hostPattern: String, keyType: String, rawKeyData: Data, comment: String? = nil) {
            self.hostPattern = hostPattern
            self.keyType = keyType
            self.rawKeyData = rawKeyData
            self.comment = comment
        }

        public var fingerprintSHA256: String {
            SSHKeyFingerprint.sha256(forRawPublicKeyBlob: rawKeyData)
        }
    }

    /// Parses an entire `known_hosts` file content into parsed line representations.
    public static func parse(contents: String) -> [KnownHostLine] {
        var lines: [KnownHostLine] = []
        let rawLines = contents.components(separatedBy: .newlines)

        for rawLine in rawLines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix("@") {
                continue
            }

            let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 2 else { continue }

            let pattern = String(parts[0])
            let type: String
            let keyBase64: String
            var comment: String?

            if parts.count >= 3 && isSupportedKeyType(String(parts[1])) {
                type = String(parts[1])
                keyBase64 = String(parts[2])
                if parts.count >= 4 {
                    comment = parts[3...].joined(separator: " ")
                }
            } else if isSupportedKeyType(String(parts[0])) {
                type = String(parts[0])
                keyBase64 = String(parts[1])
            } else {
                guard parts.count >= 3 else { continue }
                type = String(parts[1])
                keyBase64 = String(parts[2])
            }

            guard let keyData = Data(base64Encoded: keyBase64) else { continue }
            lines.append(KnownHostLine(
                hostPattern: pattern,
                keyType: type,
                rawKeyData: keyData,
                comment: comment
            ))
        }

        return lines
    }

    /// Serializes a host entry into standard OpenSSH line format.
    public static func format(
        host: String,
        port: Int,
        keyType: String,
        keyData: Data,
        comment: String? = nil
    ) -> String {
        let hostSpec: String
        if port == 22 {
            hostSpec = host
        } else {
            hostSpec = "[\(host)]:\(port)"
        }
        let base64 = keyData.base64EncodedString()
        if let comment, !comment.isEmpty {
            return "\(hostSpec) \(keyType) \(base64) \(comment)"
        }
        return "\(hostSpec) \(keyType) \(base64)"
    }

    /// Determines if a host pattern matches a target host and port.
    public static func matches(pattern: String, host: String, port: Int) -> Bool {
        let targetHostSpec = port == 22 ? host.lowercased() : "[\(host.lowercased())]:\(port)"

        if pattern.hasPrefix("|1|") {
            return matchesHashedPattern(pattern: pattern, hostSpec: targetHostSpec)
        }

        let segments = pattern.split(separator: ",").map { String($0).lowercased() }
        for segment in segments {
            if segment == targetHostSpec || (port == 22 && segment == host.lowercased()) {
                return true
            }
        }
        return false
    }

    private static func matchesHashedPattern(pattern: String, hostSpec: String) -> Bool {
        // Format: |1|salt_base64|hash_base64
        let components = pattern.split(separator: "|")
        guard components.count >= 3,
              let saltData = Data(base64Encoded: String(components[1])),
              let expectedHashData = Data(base64Encoded: String(components[2])),
              let hostData = hostSpec.data(using: .utf8)
        else {
            return false
        }

        let key = SymmetricKey(data: saltData)
        let mac = HMAC<Insecure.SHA1>.authenticationCode(for: hostData, using: key)
        return Data(mac) == expectedHashData
    }

    private static func isSupportedKeyType(_ type: String) -> Bool {
        let validTypes = [
            "ssh-ed25519", "ecdsa-sha2-nistp256", "ecdsa-sha2-nistp384",
            "ecdsa-sha2-nistp521", "ssh-rsa", "rsa-sha2-256", "rsa-sha2-512"
        ]
        return validTypes.contains(type)
    }
}
