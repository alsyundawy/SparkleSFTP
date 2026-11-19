import Foundation
import SparkleCore
import SparkleSecurity

/// Builder and validator for remote network diagnostic commands.
public enum RemoteNetworkDiagnostics {
    /// Validates a hostname or IP address to prevent shell metacharacter injection (CWE-78).
    public static func sanitizeHost(_ host: String) throws -> String {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AppError.invalidConfiguration("Host target cannot be empty.")
        }
        guard trimmed.range(of: "^[a-zA-Z0-9.:_-]+$", options: .regularExpression) != nil else {
            throw AppError.invalidConfiguration("Host '\(host)' contains invalid characters.")
        }
        return trimmed
    }

    /// Constructs a safe ping command.
    public static func buildPingCommand(host: String, count: Int = 4) throws -> String {
        let cleanHost = try sanitizeHost(host)
        let clampedCount = max(1, min(20, count))
        return "ping -c \(clampedCount) \(cleanHost)"
    }

    /// Constructs a safe traceroute command.
    public static func buildTracerouteCommand(host: String, maxHops: Int = 30) throws -> String {
        let cleanHost = try sanitizeHost(host)
        let clampedHops = max(1, min(64, maxHops))
        return "traceroute -m \(clampedHops) \(cleanHost)"
    }

    /// Returns the command string to inspect the active network routing table.
    public static func buildRouteInspectionCommand() -> String {
        "ip route 2>/dev/null || netstat -rn"
    }

    /// Returns the command string to inspect listening network sockets.
    public static func buildListeningSocketsCommand() -> String {
        "ss -tulpn 2>/dev/null || netstat -tulpn 2>/dev/null || lsof -i -P -n"
    }
}
