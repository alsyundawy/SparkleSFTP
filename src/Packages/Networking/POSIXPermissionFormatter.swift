import Foundation
import SparkleCore

/// Bidirectional POSIX permission converter and security utility.
public enum POSIXPermissionFormatter {
    /// Formats raw permissions into a standard 4-digit octal string (e.g. `0755`, `0644`).
    public static func formatOctal(_ permissions: UInt32) -> String {
        let masked = permissions & 0o7777
        return String(format: "%04o", masked)
    }

    /// Formats raw permissions into a standard 9-character symbolic string (e.g. `rwxr-xr-x`, `rw-r--r--`).
    public static func formatSymbolic(_ permissions: UInt32) -> String {
        var result = ""
        let masks: [(UInt32, Character)] = [
            (0o400, "r"), (0o200, "w"), (0o100, "x"),
            (0o040, "r"), (0o020, "w"), (0o010, "x"),
            (0o004, "r"), (0o002, "w"), (0o001, "x")
        ]
        for (mask, char) in masks {
            if (permissions & mask) != 0 {
                result.append(char)
            } else {
                result.append("-")
            }
        }
        return result
    }

    /// Parses a 9-character symbolic permission string (e.g. `rwxr-xr-x`) into raw octal bits.
    public static func parseSymbolic(_ symbolic: String) -> UInt32? {
        let trimmed = symbolic.trimmingCharacters(in: .whitespacesAndNewlines)
        let chars = trimmed.hasPrefix("-") && trimmed.count == 10 ? String(trimmed.dropFirst()) : trimmed
        guard chars.count == 9 else { return nil }

        let expectedPairs: [(Character, UInt32)] = [
            ("r", 0o400), ("w", 0o200), ("x", 0o100),
            ("r", 0o040), ("w", 0o020), ("x", 0o010),
            ("r", 0o004), ("w", 0o002), ("x", 0o001)
        ]
        var perms: UInt32 = 0
        let charArray = Array(chars)
        for (idx, pair) in expectedPairs.enumerated() {
            let actual = charArray[idx]
            if actual == pair.0 {
                perms |= pair.1
            } else if actual != "-" {
                return nil
            }
        }
        return perms
    }

    /// Parses an octal string (e.g. `"755"`, `"0755"`) into UInt32 bits.
    public static func parseOctal(_ octalString: String) -> UInt32? {
        let trimmed = octalString.trimmingCharacters(in: .whitespacesAndNewlines)
        return UInt32(trimmed, radix: 8)
    }

    /// Adds execute bits for user, group, and others (`chmod +x`).
    public static func makeExecutable(_ permissions: UInt32) -> UInt32 {
        permissions | 0o111
    }

    /// Clamps permissions to user read/write only (`0600`) for private keys and sensitive configs.
    public static func securePrivate(_ permissions: UInt32) -> UInt32 {
        0o600
    }
}
