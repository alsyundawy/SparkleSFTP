import Foundation
import SparkleCore
import SparkleSecurity

/// Remote Linux server management and telemetry inspection controller.
public enum RemoteSystemManager {
    /// Permitted systemd service targets to prevent arbitrary shell command execution (CWE-78).
    public static let allowedServices: Set<String> = [
        "nginx", "apache2", "httpd", "php-fpm", "php8.2-fpm", "php8.3-fpm", "php8.4-fpm",
        "mariadb", "mysql", "postgresql", "docker", "sshd", "ssh", "named", "bind9",
        "ufw", "fail2ban", "redis", "memcached"
    ]

    public enum ServiceAction: String, Sendable, CaseIterable {
        case status
        case start
        case stop
        case restart
        case reload
    }

    public struct ServiceStatus: Sendable, Equatable {
        public let service: String
        public let isActive: Bool
        public let isEnabled: Bool
        public let rawOutput: String

        public init(service: String, isActive: Bool, isEnabled: Bool, rawOutput: String) {
            self.service = service
            self.isActive = isActive
            self.isEnabled = isEnabled
            self.rawOutput = rawOutput
        }
    }

    /// Builds a sanitized, safe `systemctl` command string.
    public static func buildSystemctlCommand(action: ServiceAction, service: String) throws -> String {
        let trimmed = service.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard allowedServices.contains(trimmed) else {
            throw AppError.invalidConfiguration("Service '\(service)' is not in the sanctioned service list.")
        }
        return "systemctl \(action.rawValue) \(trimmed)"
    }

    /// System load average model (from `/proc/loadavg`).
    public struct LoadAverage: Sendable, Equatable {
        public let oneMinute: Double
        public let fiveMinute: Double
        public let fifteenMinute: Double

        public init(oneMinute: Double, fiveMinute: Double, fifteenMinute: Double) {
            self.oneMinute = oneMinute
            self.fiveMinute = fiveMinute
            self.fifteenMinute = fifteenMinute
        }
    }

    /// System memory usage model (from `free -m`).
    public struct MemoryTelemetry: Sendable, Equatable {
        public let totalMB: Int
        public let usedMB: Int
        public let freeMB: Int
        public let availableMB: Int

        public init(totalMB: Int, usedMB: Int, freeMB: Int, availableMB: Int) {
            self.totalMB = totalMB
            self.usedMB = usedMB
            self.freeMB = freeMB
            self.availableMB = availableMB
        }

        public var percentUsed: Double {
            guard totalMB > 0 else { return 0.0 }
            return (Double(usedMB) / Double(totalMB)) * 100.0
        }
    }

    /// Disk partition quota model (from `df -h`).
    public struct DiskPartition: Sendable, Equatable {
        public let filesystem: String
        public let total: String
        public let used: String
        public let available: String
        public let percent: String
        public let mountPoint: String

        public init(
            filesystem: String,
            total: String,
            used: String,
            available: String,
            percent: String,
            mountPoint: String
        ) {
            self.filesystem = filesystem
            self.total = total
            self.used = used
            self.available = available
            self.percent = percent
            self.mountPoint = mountPoint
        }
    }

    /// Parses `/proc/loadavg` string (e.g. `0.15 0.22 0.18 1/245 12345`).
    public static func parseLoadAverage(from rawText: String) -> LoadAverage? {
        let parts = rawText.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 3,
              let min1 = Double(parts[0]),
              let min5 = Double(parts[1]),
              let min15 = Double(parts[2])
        else {
            return nil
        }
        return LoadAverage(oneMinute: min1, fiveMinute: min5, fifteenMinute: min15)
    }

    /// Parses `free -m` output for memory metrics.
    public static func parseFreeMemory(from rawText: String) -> MemoryTelemetry? {
        let lines = rawText.components(separatedBy: .newlines)
        for line in lines {
            let lower = line.lowercased()
            if lower.hasPrefix("mem:") {
                let parts = line.split(separator: " ", omittingEmptySubsequences: true)
                guard parts.count >= 4,
                      let total = Int(parts[1]),
                      let used = Int(parts[2]),
                      let free = Int(parts[3])
                else {
                    continue
                }
                let available = parts.count >= 7 ? (Int(parts[6]) ?? free) : free
                return MemoryTelemetry(totalMB: total, usedMB: used, freeMB: free, availableMB: available)
            }
        }
        return nil
    }

    /// Parses `df -h` output into disk partition models.
    public static func parseDiskUsage(from rawText: String) -> [DiskPartition] {
        var partitions: [DiskPartition] = []
        let lines = rawText.components(separatedBy: .newlines)
        for line in lines.dropFirst() {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 6 else { continue }
            let filesystemName = String(parts[0])
            let total = String(parts[1])
            let used = String(parts[2])
            let avail = String(parts[3])
            let pct = String(parts[4])
            let mount = String(parts[5])
            partitions.append(DiskPartition(
                filesystem: filesystemName,
                total: total,
                used: used,
                available: avail,
                percent: pct,
                mountPoint: mount
            ))
        }
        return partitions
    }
}
