import Crypto
import Foundation
import NIOCore
import NIOSSH
import SparkleCore

/// Fingerprint utilities matching OpenSSH `SHA256:<base64-no-padding>` format.
public enum SSHKeyFingerprint {
    public static func sha256(for publicKey: NIOSSHPublicKey) -> String {
        let openSSHText = String(openSSHPublicKey: publicKey)
        let parts = openSSHText.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count >= 2, let rawBlob = Data(base64Encoded: String(parts[1])) else {
            return "SHA256:unknown"
        }
        return sha256(forRawPublicKeyBlob: rawBlob)
    }

    public static func sha256(forRawPublicKeyBlob blob: Data) -> String {
        let digest = SHA256.hash(data: blob)
        let encoded = Data(digest).base64EncodedString().replacingOccurrences(of: "=", with: "")
        return "SHA256:\(encoded)"
    }

    public static func keyAlgorithm(for publicKey: NIOSSHPublicKey) -> String {
        let openSSHText = String(openSSHPublicKey: publicKey)
        return openSSHText.split(separator: " ").first.map(String.init) ?? "unknown"
    }
}

/// Parses unencrypted OpenSSH v1 (`openssh-key-v1`) private keys supported by apple/swift-nio-ssh.
public enum PrivateKeyParser {
    private static let openSSHBegin = "-----BEGIN OPENSSH PRIVATE KEY-----"
    private static let openSSHEnd = "-----END OPENSSH PRIVATE KEY-----"
    private static let openSSHMagic = Array("openssh-key-v1\0".utf8)

    public static func parsePrivateKey(pemString: String) throws -> NIOSSHPrivateKey {
        let trimmed = pemString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains(openSSHBegin), trimmed.contains(openSSHEnd) else {
            throw AppError.invalidPrivateKey(
                reason: "Unsupported format; provide an OpenSSH key (Ed25519 or ECDSA P-256/384/521)."
            )
        }

        let body = trimmed
            .replacingOccurrences(of: openSSHBegin, with: "")
            .replacingOccurrences(of: openSSHEnd, with: "")
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()

        guard let raw = Data(base64Encoded: body) else {
            throw AppError.invalidPrivateKey(reason: "Base64 decoding failed.")
        }

        return try parseOpenSSHBinary(raw)
    }

    private static func parseOpenSSHBinary(_ data: Data) throws -> NIOSSHPrivateKey {
        var reader = BinaryReader(data: data)
        let magic = try reader.readBytes(count: openSSHMagic.count)
        guard magic == openSSHMagic else {
            throw AppError.invalidPrivateKey(reason: "Missing openssh-key-v1 header.")
        }

        let cipherName = try reader.readSSHStringAsString()
        let kdfName = try reader.readSSHStringAsString()
        _ = try reader.readSSHString()

        guard cipherName == "none", kdfName == "none" else {
            throw AppError.invalidPrivateKey(
                reason: "Passphrase-encrypted OpenSSH keys require ssh-agent or unencrypted Keychain storage."
            )
        }

        let keyCount = try reader.readUInt32()
        guard keyCount >= 1 else {
            throw AppError.invalidPrivateKey(reason: "Key container has zero keys.")
        }

        _ = try reader.readSSHString()
        let privateBlob = try reader.readSSHString()
        var priv = BinaryReader(data: privateBlob)
        guard try priv.readUInt32() == priv.readUInt32() else {
            throw AppError.invalidPrivateKey(reason: "Private key checkints mismatch.")
        }

        let keyType = try priv.readSSHStringAsString()
        return try decodePrivateKey(type: keyType, reader: &priv)
    }

    private static func decodePrivateKey(type keyType: String, reader: inout BinaryReader) throws -> NIOSSHPrivateKey {
        switch keyType {
        case "ssh-ed25519":
            _ = try reader.readSSHString()
            let privAndPub = try reader.readSSHString()
            guard privAndPub.count >= 32 else {
                throw AppError.invalidPrivateKey(reason: "Invalid Ed25519 key length.")
            }
            let signingKey = try Curve25519.Signing.PrivateKey(rawRepresentation: privAndPub.prefix(32))
            return NIOSSHPrivateKey(ed25519Key: signingKey)

        case "ecdsa-sha2-nistp256", "ecdsa-sha2-nistp384", "ecdsa-sha2-nistp521":
            return try decodeECDSAKey(type: keyType, reader: &reader)

        default:
            throw AppError.invalidPrivateKey(
                reason: "Key type '\(keyType)' is unsupported (use Ed25519 or ECDSA P-256/384/521)."
            )
        }
    }

    private static func decodeECDSAKey(type keyType: String, reader: inout BinaryReader) throws -> NIOSSHPrivateKey {
        let expectedCurve: String
        let byteCount: Int
        switch keyType {
        case "ecdsa-sha2-nistp256":
            expectedCurve = "nistp256"
            byteCount = 32
        case "ecdsa-sha2-nistp384":
            expectedCurve = "nistp384"
            byteCount = 48
        default:
            expectedCurve = "nistp521"
            byteCount = 66
        }

        let curve = try reader.readSSHStringAsString()
        guard curve == expectedCurve else {
            throw AppError.invalidPrivateKey(reason: "Unexpected curve \(curve).")
        }
        _ = try reader.readSSHString()
        let scalar = try reader.readMPIntUnsigned(byteCount: byteCount)
        switch byteCount {
        case 32: return try NIOSSHPrivateKey(p256Key: P256.Signing.PrivateKey(rawRepresentation: scalar))
        case 48: return try NIOSSHPrivateKey(p384Key: P384.Signing.PrivateKey(rawRepresentation: scalar))
        default: return try NIOSSHPrivateKey(p521Key: P521.Signing.PrivateKey(rawRepresentation: scalar))
        }
    }
}

private struct BinaryReader {
    private let bytes: [UInt8]
    private var offset = 0

    init(data: Data) {
        bytes = Array(data)
    }

    mutating func readUInt32() throws -> UInt32 {
        let slice = try readBytes(count: 4)
        return (UInt32(slice[0]) << 24)
            | (UInt32(slice[1]) << 16)
            | (UInt32(slice[2]) << 8)
            | UInt32(slice[3])
    }

    mutating func readBytes(count: Int) throws -> [UInt8] {
        guard count >= 0, offset + count <= bytes.count else {
            throw AppError.invalidPrivateKey(reason: "Truncated OpenSSH key payload.")
        }
        let slice = Array(bytes[offset ..< (offset + count)])
        offset += count
        return slice
    }

    mutating func readSSHString() throws -> Data {
        let length = try Int(readUInt32())
        return try Data(readBytes(count: length))
    }

    mutating func readSSHStringAsString() throws -> String {
        let data = try readSSHString()
        guard let str = String(data: data, encoding: .utf8) else {
            throw AppError.invalidPrivateKey(reason: "Non-UTF8 string field in OpenSSH key.")
        }
        return str
    }

    mutating func readMPIntUnsigned(byteCount: Int) throws -> Data {
        var raw = try readSSHString()
        if raw.count > byteCount, raw.first == 0 {
            raw = raw.dropFirst()
        }
        if raw.count < byteCount {
            raw = Data(repeating: 0, count: byteCount - raw.count) + raw
        }
        guard raw.count == byteCount else {
            throw AppError.invalidPrivateKey(reason: "Invalid ECDSA scalar byte length.")
        }
        return raw
    }
}
