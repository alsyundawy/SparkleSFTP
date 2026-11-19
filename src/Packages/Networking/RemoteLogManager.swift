import Foundation
import SparkleCore
import SparkleSecurity

/// Remote server log stream and inspection helper.
public enum RemoteLogManager {
    /// Common standard Linux system and service log locations.
    public static let standardLogPaths: [String] = [
        "/var/log/syslog",
        "/var/log/messages",
        "/var/log/auth.log",
        "/var/log/nginx/error.log",
        "/var/log/nginx/access.log",
        "/var/log/apache2/error.log",
        "/var/log/apache2/access.log",
        "/var/log/mail.log",
        "/var/log/fail2ban.log"
    ]

    /// Constructs a safe, shell-escaped `tail` command for inspecting server logs.
    public static func buildTailCommand(
        path: String,
        lines: Int = 500,
        follow: Bool = false,
        useSudo: Bool = false
    ) throws -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AppError.invalidConfiguration("Log path cannot be empty.")
        }
        let quoted = try PathValidator.escapePOSIXSingleQuoted(trimmed)
        let clamped = max(10, min(5000, lines))
        let followFlag = follow ? " -f" : ""
        let sudoPrefix = useSudo ? "sudo -n " : ""
        return "\(sudoPrefix)tail -n \(clamped)\(followFlag) \(quoted)"
    }
}
