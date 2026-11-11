import Foundation

/// Validates Sparkle Ed25519 public key & HTTPS appcast configuration before enabling auto-updates (SEC-006).
public enum UpdateConfigurationValidator {
    public static func isValidHTTPSFeed(_ feedURLString: String?) -> Bool {
        guard let raw = feedURLString?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: raw),
              url.scheme?.lowercased() == "https",
              let host = url.host,
              !host.isEmpty
        else {
            return false
        }
        return true
    }

    public static func isValidEd25519PublicKey(_ publicKey: String?) -> Bool {
        guard let trimmed = publicKey?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return false
        }
        let upper = trimmed.uppercased()
        guard !upper.contains("REPLACE_WITH"), !upper.contains("PLACEHOLDER"),
              let decoded = Data(base64Encoded: trimmed), decoded.count == 32
        else {
            return false
        }
        return true
    }
}
