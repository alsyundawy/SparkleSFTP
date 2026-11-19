import Foundation

/// Security audit assessment for remote SSH server versions (e.g. CVE-2024-6387 regreSSHion).
public struct SSHServerAuditReport: Sendable, Equatable {
    public let rawBanner: String
    public let softwareVersion: String
    public let isVulnerableToCVE20246387: Bool
    public let advisoryMessage: String?

    public init(
        rawBanner: String,
        softwareVersion: String,
        isVulnerableToCVE20246387: Bool,
        advisoryMessage: String? = nil
    ) {
        self.rawBanner = rawBanner
        self.softwareVersion = softwareVersion
        self.isVulnerableToCVE20246387 = isVulnerableToCVE20246387
        self.advisoryMessage = advisoryMessage
    }
}

/// Remote OpenSSH server vulnerability scanner auditing version banners against CVE-2024-6387 (regreSSHion).
public enum SSHServerAuditor: Sendable {
    /// Evaluates remote server identification string (RFC 4253 §4.2: SSH-protoversion-softwareversion SP comments).
    /// Detects OpenSSH 8.5p1 through 9.7p1 (CVE-2024-6387 regreSSHion unauthenticated RCE on glibc systems).
    public static func audit(banner: String) -> SSHServerAuditReport {
        let trimmed = banner.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("SSH-") else {
            return SSHServerAuditReport(
                rawBanner: banner,
                softwareVersion: "Unknown",
                isVulnerableToCVE20246387: false
            )
        }

        // Format example: SSH-2.0-OpenSSH_8.9p1 Ubuntu-3ubuntu0.10
        let parts = trimmed.components(separatedBy: " ")
        let versionToken = parts.first ?? trimmed
        let tokens = versionToken.components(separatedBy: "-")
        guard tokens.count >= 3 else {
            return SSHServerAuditReport(
                rawBanner: banner,
                softwareVersion: versionToken,
                isVulnerableToCVE20246387: false
            )
        }

        let software = tokens.dropFirst(2).joined(separator: "-")
        let isVuln = isVulnerableOpenSSH(software)
        let advisory = isVuln
            ? "Server reports \(software), vulnerable to CVE-2024-6387 regreSSHion RCE. Upgrade OpenSSH to >= 9.8p1."
            : nil

        return SSHServerAuditReport(
            rawBanner: banner,
            softwareVersion: software,
            isVulnerableToCVE20246387: isVuln,
            advisoryMessage: advisory
        )
    }

    /// Checks if the software string represents an OpenSSH version between 8.5p1 and 9.7p1.
    public static func isVulnerableOpenSSH(_ software: String) -> Bool {
        guard software.hasPrefix("OpenSSH_") else { return false }
        let verPart = software.dropFirst("OpenSSH_".count)
        let components = verPart.components(separatedBy: ".")
        guard components.count >= 2,
              let major = Int(components[0]) else {
            return false
        }
        let minorString = components[1].prefix(while: { $0.isNumber })
        guard let minor = Int(minorString) else { return false }

        if major == 8 {
            return minor >= 5
        } else if major == 9 {
            return minor <= 7
        }
        return false
    }
}
