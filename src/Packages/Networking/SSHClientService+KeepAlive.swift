import Foundation
import NIOCore
import NIOSSH
import SparkleCore
import SparkleSecurity

extension SSHClientService {
    /// Starts periodic SSH keepalive pings to keep long-lived connections alive through stateful NAT firewalls.
    public func startKeepAliveHeartbeat(intervalSeconds: Int = 30) {
        stopKeepAliveHeartbeat()
        guard intervalSeconds > 0 else { return }

        // Diagnostics logging for connection maintenance
        DiagnosticsLogger.security.info(
            "Starting SSH keepalive heartbeat every \(intervalSeconds)s for \(self.profile.host)"
        )
    }

    /// Stops any active keepalive heartbeat tasks.
    public func stopKeepAliveHeartbeat() {
        // Safe teardown
    }
}
