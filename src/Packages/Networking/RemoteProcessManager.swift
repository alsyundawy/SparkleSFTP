import Foundation
import SparkleCore
import SparkleSecurity

/// Signal sent to remote processes.
public enum ProcessSignal: Int, Sendable, CaseIterable {
    case term = 15
    case kill = 9
}

/// Represents a running process on a remote Linux server.
public struct RemoteProcess: Identifiable, Sendable, Equatable {
    public var id: Int { pid }
    public let pid: Int
    public let user: String
    public let cpuPercent: Double
    public let memPercent: Double
    public let command: String

    public init(pid: Int, user: String, cpuPercent: Double, memPercent: Double, command: String) {
        self.pid = pid
        self.user = user
        self.cpuPercent = cpuPercent
        self.memPercent = memPercent
        self.command = command
    }
}

/// Actions available for remote Docker container management.
public enum DockerAction: String, Sendable, CaseIterable {
    case start
    case stop
    case restart
    case logs
}

/// Represents a Docker container instance on a remote server.
public struct DockerContainer: Identifiable, Sendable, Equatable {
    public let id: String
    public let image: String
    public let name: String
    public let status: String
    public let state: String

    public init(id: String, image: String, name: String, status: String, state: String) {
        self.id = id
        self.image = image
        self.name = name
        self.status = status
        self.state = state
    }

    public var isRunning: Bool {
        state.lowercased() == "running"
    }
}

/// Controller for parsing process lists and managing Docker containers remotely.
public enum RemoteProcessManager {
    /// Builds a sanitized kill command, strictly rejecting PID <= 1 to protect critical system services.
    public static func buildKillCommand(pid: Int, signal: ProcessSignal = .term) throws -> String {
        guard pid > 1 else {
            throw AppError.invalidConfiguration("Cannot signal PID \(pid): system root processes are protected.")
        }
        return "kill -\(signal.rawValue) \(pid)"
    }

    /// Parses the standard output of `ps aux --sort=-%cpu` into strongly typed `RemoteProcess` models.
    public static func parseProcessList(from rawOutput: String) -> [RemoteProcess] {
        var processes: [RemoteProcess] = []
        let lines = rawOutput.components(separatedBy: .newlines)
        for line in lines.dropFirst() {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 11,
                  let pid = Int(parts[1]),
                  let cpu = Double(parts[2]),
                  let mem = Double(parts[3])
            else {
                continue
            }
            let user = String(parts[0])
            let command = parts.dropFirst(10).joined(separator: " ")
            processes.append(RemoteProcess(
                pid: pid,
                user: user,
                cpuPercent: cpu,
                memPercent: mem,
                command: command
            ))
        }
        return processes
    }

    /// Builds a sanitized Docker command for managing remote container instances.
    public static func buildDockerCommand(
        action: DockerAction,
        containerId: String,
        tailLines: Int = 200
    ) throws -> String {
        let trimmed = containerId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.range(of: "^[a-zA-Z0-9_.-]+$", options: .regularExpression) != nil else {
            throw AppError.invalidConfiguration("Invalid Docker container identifier: '\(containerId)'")
        }
        switch action {
        case .logs:
            let clamped = max(10, min(1000, tailLines))
            return "docker logs --tail \(clamped) \(trimmed)"
        default:
            return "docker \(action.rawValue) \(trimmed)"
        }
    }

    /// Parses tab-delimited output from `docker ps -a --format`.
    /// Format: `{{.ID}}\t{{.Image}}\t{{.Names}}\t{{.Status}}\t{{.State}}`.
    public static func parseDockerContainers(from rawOutput: String) -> [DockerContainer] {
        var containers: [DockerContainer] = []
        let lines = rawOutput.components(separatedBy: .newlines)
        for line in lines {
            let parts = line.components(separatedBy: "\t")
            guard parts.count >= 5 else { continue }
            containers.append(DockerContainer(
                id: parts[0].trimmingCharacters(in: .whitespaces),
                image: parts[1].trimmingCharacters(in: .whitespaces),
                name: parts[2].trimmingCharacters(in: .whitespaces),
                status: parts[3].trimmingCharacters(in: .whitespaces),
                state: parts[4].trimmingCharacters(in: .whitespaces)
            ))
        }
        return containers
    }
}
