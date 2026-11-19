import Foundation
import Network
import SparkleCore

/// Result of probing a remote TCP network port.
public enum PortStatus: Sendable, Equatable {
    case open
    case closed
    case timeout
    case failed(String)
}

/// Strongly typed port reachability probe record.
public struct PortProbeResult: Identifiable, Sendable, Equatable {
    public var id: UInt16 { port }
    public let port: UInt16
    public let serviceName: String
    public let status: PortStatus
    public let latencyMs: Double?

    public init(port: UInt16, serviceName: String, status: PortStatus, latencyMs: Double? = nil) {
        self.port = port
        self.serviceName = serviceName
        self.status = status
        self.latencyMs = latencyMs
    }
}

/// Service for probing TCP port reachability on remote hosts.
public enum PortChecker {
    private final class ResumeBox: @unchecked Sendable { // JUSTIFICATION: Protected via internal NSLock.
        private let lock = NSLock()
        private var hasResumed = false

        func executeOnce(_ action: () -> Void) {
            lock.lock()
            defer { lock.unlock() }
            if !hasResumed {
                hasResumed = true
                action()
            }
        }
    }

    /// Standard network ports monitored by SparkleSFTP.
    public static let defaultMonitoredPorts: [(UInt16, String)] = [
        (22, "SSH / SFTP"),
        (21, "FTP Control"),
        (990, "FTPS Implicit"),
        (80, "HTTP"),
        (443, "HTTPS"),
        (3306, "MySQL / MariaDB"),
        (5432, "PostgreSQL"),
        (6379, "Redis")
    ]

    private static func handleStateChange(
        _ state: NWConnection.State,
        startTime: DispatchTime,
        port: UInt16,
        serviceName: String,
        resumeOnce: @escaping @Sendable (PortProbeResult) -> Void
    ) {
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000.0
        switch state {
        case .ready:
            resumeOnce(PortProbeResult(
                port: port,
                serviceName: serviceName,
                status: .open,
                latencyMs: elapsedMs
            ))
        case .failed:
            resumeOnce(PortProbeResult(
                port: port,
                serviceName: serviceName,
                status: .closed,
                latencyMs: elapsedMs
            ))
        default:
            break
        }
    }

    /// Probes a specific TCP port with a bounded timeout in seconds.
    public static func probePort(
        host: String,
        port: UInt16,
        serviceName: String = "",
        timeoutSeconds: TimeInterval = 3.0
    ) async -> PortProbeResult {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty,
              let nwPort = NWEndpoint.Port(rawValue: port) else {
            return PortProbeResult(
                port: port,
                serviceName: serviceName,
                status: .failed("Invalid host or port")
            )
        }

        let nwHost = NWEndpoint.Host(trimmedHost)
        let connection = NWConnection(host: nwHost, port: nwPort, using: .tcp)
        let queue = DispatchQueue(label: "org.sparklesftp.portchecker.\(port)")
        let startTime = DispatchTime.now()
        let box = ResumeBox()

        return await withCheckedContinuation { continuation in
            let resumeOnce: @Sendable (PortProbeResult) -> Void = { result in
                box.executeOnce {
                    connection.cancel()
                    continuation.resume(returning: result)
                }
            }

            queue.asyncAfter(deadline: .now() + timeoutSeconds) {
                resumeOnce(PortProbeResult(port: port, serviceName: serviceName, status: .timeout))
            }

            connection.stateUpdateHandler = { state in
                handleStateChange(
                    state,
                    startTime: startTime,
                    port: port,
                    serviceName: serviceName,
                    resumeOnce: resumeOnce
                )
            }
            connection.start(queue: queue)
        }
    }
}
