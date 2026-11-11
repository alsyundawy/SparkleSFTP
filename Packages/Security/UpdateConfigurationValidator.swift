import Foundation

/// Validates Sparkle Ed25519 public key & HTTPS appcast configuration before enabling auto-updates (SEC-006).
public enum UpdateConfigurationValidator {
    public static func isValidHTTPSFeed(_ feedURLString: String?) -> Bool {
        validatedHTTPSURL(feedURLString) != nil
    }

    public static func validatedHTTPSURL(_ feedURLString: String?) -> URL? {
        guard let raw = feedURLString?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: raw),
              url.scheme?.lowercased() == "https",
              let host = url.host,
              !host.isEmpty
        else {
            return nil
        }
        return url
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

    /// Compares semantic versions such as `"v0.3.0"` vs `"0.2.0"` cleanly without external dependencies.
    public static func isNewerVersion(_ candidateTag: String, than currentVersion: String) -> Bool {
        let lhs = numericComponents(from: candidateTag)
        let rhs = numericComponents(from: currentVersion)
        let count = max(lhs.count, rhs.count)
        for index in 0 ..< count {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left != right {
                return left > right
            }
        }
        return false
    }

    private static func numericComponents(from raw: String) -> [Int] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutLeadingV = trimmed.hasPrefix("v") || trimmed.hasPrefix("V")
            ? String(trimmed.dropFirst())
            : trimmed
        let core = withoutLeadingV.split(separator: "-", maxSplits: 1).first.map(String.init) ?? withoutLeadingV
        return core.split(separator: ".").map { Int($0) ?? 0 }
    }
}
