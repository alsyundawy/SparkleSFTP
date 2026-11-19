import Foundation
import SparkleCore

/// Precision network latency and round-trip time (RTT) probing metrics.
public struct HostLatencyMetrics: Sendable, Equatable {
    public let averageMs: Double
    public let minimumMs: Double
    public let maximumMs: Double
    public let jitterMs: Double
    public let sampleCount: Int

    public init(averageMs: Double, minimumMs: Double, maximumMs: Double, jitterMs: Double, sampleCount: Int) {
        self.averageMs = averageMs
        self.minimumMs = minimumMs
        self.maximumMs = maximumMs
        self.jitterMs = jitterMs
        self.sampleCount = sampleCount
    }
}

/// Precision round-trip time (RTT) and latency probe for remote hosts.
public enum HostLatencyProbe {
    /// Collects latency probe samples over TCP to calculate average RTT and network jitter.
    public static func probe(
        host: String,
        port: UInt16 = 22,
        sampleCount: Int = 3,
        timeoutSeconds: TimeInterval = 2.0
    ) async -> HostLatencyMetrics? {
        let count = max(1, min(5, sampleCount))
        var samples: [Double] = []

        for index in 0 ..< count {
            try? await Task.sleep(nanoseconds: index == 0 ? 0 : 50_000_000)
            let result = await PortChecker.probePort(
                host: host,
                port: port,
                serviceName: "latency-probe",
                timeoutSeconds: timeoutSeconds
            )
            if result.status == .open, let latencyMs = result.latencyMs {
                samples.append(latencyMs)
            }
        }

        guard !samples.isEmpty else { return nil }

        let minMs = samples.min() ?? 0.0
        let maxMs = samples.max() ?? 0.0
        let total = samples.reduce(0.0, +)
        let avgMs = total / Double(samples.count)
        let jitter = maxMs - minMs

        return HostLatencyMetrics(
            averageMs: avgMs,
            minimumMs: minMs,
            maximumMs: maxMs,
            jitterMs: jitter,
            sampleCount: samples.count
        )
    }
}
