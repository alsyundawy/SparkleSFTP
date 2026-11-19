import Foundation

/// Key exchange algorithm descriptors classifying Post-Quantum (PQ) hybrids and classical algorithms.
public enum SSHKeyExchangeAlgorithm: String, Sendable, CaseIterable {
    // Post-quantum hybrid algorithms (OpenSSH 9.0+ / 10.x standards)
    case mlkem768x25519SHA256 = "mlkem768x25519-sha256"
    case sntrup761x25519SHA512OpenSSH = "sntrup761x25519-sha512@openssh.com"
    case sntrup761x25519SHA512 = "sntrup761x25519-sha512"

    // Classical ECDH / DH algorithms
    case curve25519SHA256 = "curve25519-sha256"
    case curve25519SHA256Libssh = "curve25519-sha256@libssh.org"
    case ecdhSHA2NISTP256 = "ecdh-sha2-nistp256"
    case ecdhSHA2NISTP384 = "ecdh-sha2-nistp384"
    case ecdhSHA2NISTP521 = "ecdh-sha2-nistp521"
    case diffieHellmanGroup16SHA512 = "diffie-hellman-group16-sha512"
    case diffieHellmanGroup14SHA256 = "diffie-hellman-group14-sha256"
    case diffieHellmanGroup14SHA1 = "diffie-hellman-group14-sha1"

    /// Whether the key exchange provides post-quantum hybrid confidentiality.
    public var isPostQuantum: Bool {
        switch self {
        case .mlkem768x25519SHA256,
             .sntrup761x25519SHA512OpenSSH,
             .sntrup761x25519SHA512:
            return true
        default:
            return false
        }
    }

    /// User-facing descriptive name of the key exchange algorithm.
    public var displayName: String {
        switch self {
        case .mlkem768x25519SHA256:
            return "ML-KEM-768 + X25519 (FIPS 203 Post-Quantum Hybrid)"
        case .sntrup761x25519SHA512OpenSSH, .sntrup761x25519SHA512:
            return "Streamlined NTRU Prime 761 + X25519 (Post-Quantum Hybrid)"
        case .curve25519SHA256, .curve25519SHA256Libssh:
            return "Curve25519 with SHA-256"
        case .ecdhSHA2NISTP256:
            return "ECDH NIST P-256 with SHA-256"
        case .ecdhSHA2NISTP384:
            return "ECDH NIST P-384 with SHA-384"
        case .ecdhSHA2NISTP521:
            return "ECDH NIST P-521 with SHA-512"
        case .diffieHellmanGroup16SHA512:
            return "Diffie-Hellman Group 16 (4096-bit) with SHA-512"
        case .diffieHellmanGroup14SHA256:
            return "Diffie-Hellman Group 14 (2048-bit) with SHA-256"
        case .diffieHellmanGroup14SHA1:
            return "Diffie-Hellman Group 14 (2048-bit) with SHA-1 (Legacy)"
        }
    }

    /// Short badge title for UI status meters.
    public var badgeTitle: String {
        isPostQuantum ? "Post-Quantum Safe (PQ)" : "Classical Security"
    }

    /// Resolves an algorithm from a raw OpenSSH negotiation identifier.
    public static func resolve(from identifier: String) -> SSHKeyExchangeAlgorithm? {
        let trimmed = identifier.trimmingCharacters(in: .whitespaces)
        return SSHKeyExchangeAlgorithm(rawValue: trimmed)
    }
}
