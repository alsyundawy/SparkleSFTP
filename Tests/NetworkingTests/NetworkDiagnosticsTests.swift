import Foundation
import SparkleCore
@testable import SparkleNetworking
import Testing

@Suite("Network Diagnostics & Port Checker Tests")
struct NetworkDiagnosticsTests {
    @Test("RemoteNetworkDiagnostics sanitizes host input and rejects injection characters")
    func testSanitizeHost() throws {
        let clean = try RemoteNetworkDiagnostics.sanitizeHost("192.168.1.1")
        #expect(clean == "192.168.1.1")

        let hostname = try RemoteNetworkDiagnostics.sanitizeHost("gateway.local")
        #expect(hostname == "gateway.local")

        #expect(throws: AppError.self) {
            _ = try RemoteNetworkDiagnostics.sanitizeHost("evil; rm -rf /")
        }
        #expect(throws: AppError.self) {
            _ = try RemoteNetworkDiagnostics.sanitizeHost("127.0.0.1$(whoami)")
        }
        #expect(throws: AppError.self) {
            _ = try RemoteNetworkDiagnostics.sanitizeHost("   ")
        }
    }

    @Test("RemoteNetworkDiagnostics constructs ping, traceroute, and route inspection commands")
    func testDiagnosticCommands() throws {
        let ping = try RemoteNetworkDiagnostics.buildPingCommand(host: "10.0.0.1", count: 5)
        #expect(ping == "ping -c 5 10.0.0.1")

        let trace = try RemoteNetworkDiagnostics.buildTracerouteCommand(host: "example.com", maxHops: 15)
        #expect(trace == "traceroute -m 15 example.com")

        let routes = RemoteNetworkDiagnostics.buildRouteInspectionCommand()
        #expect(routes.contains("ip route") || routes.contains("netstat"))

        let sockets = RemoteNetworkDiagnostics.buildListeningSocketsCommand()
        #expect(sockets.contains("ss -tulpn") || sockets.contains("netstat"))
    }

    @Test("PortChecker rejects invalid host parameters gracefully")
    func testPortCheckerInvalidHost() async {
        let res = await PortChecker.probePort(host: "", port: 22, serviceName: "SSH")
        #expect(res.status == .failed("Invalid host or port"))
    }

    @Test("HostLatencyProbe returns nil for unreachable or invalid hosts")
    func testHostLatencyProbeInvalidHost() async {
        let metrics = await HostLatencyProbe.probe(host: "", port: 22, sampleCount: 1)
        #expect(metrics == nil)
    }
}
