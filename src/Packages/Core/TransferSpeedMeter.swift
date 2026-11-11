import Foundation

/// Thread-safe EWMA bandwidth estimator and throttled transfer progress emitter shared across protocol adapters.
public final class TransferSpeedMeter: @unchecked Sendable { // JUSTIFICATION: NSLock protects timing & EWMA state.
    private let lock = NSLock()
    private let totalBytes: Int64
    private let initialOffset: Int64
    private let minEmitInterval: Duration
    private let startTime: ContinuousClock.Instant

    private var lastSampleTime: ContinuousClock.Instant
    private var lastEmitTime: ContinuousClock.Instant?
    private var lastSampleBytes: Int64
    private var smoothedBytesPerSecond: Double = 0

    public init(
        totalBytes: Int64,
        initialOffset: Int64 = 0,
        minEmitInterval: Duration = .milliseconds(60)
    ) {
        let now = ContinuousClock.now
        self.totalBytes = max(0, totalBytes)
        self.initialOffset = max(0, initialOffset)
        self.minEmitInterval = minEmitInterval
        startTime = now
        lastSampleTime = now
        lastSampleBytes = max(0, initialOffset)
    }

    public func record(absoluteBytes: Int64, totalOverride: Int64? = nil, force: Bool = false) -> TransferProgress? {
        lock.lock()
        defer { lock.unlock() }

        let clampedBytes = max(lastSampleBytes, absoluteBytes)
        let resolvedTotal = max(clampedBytes, max(totalOverride ?? 0, totalBytes))
        let now = ContinuousClock.now
        let isComplete = resolvedTotal > 0 && clampedBytes >= resolvedTotal

        if !force, !isComplete, let lastEmitTime, now - lastEmitTime < minEmitInterval {
            return nil
        }

        let rate = computeSmoothedRateLocked(now: now, absoluteBytes: clampedBytes)
        lastEmitTime = now
        return TransferProgress(
            bytesTransferred: clampedBytes,
            totalBytes: resolvedTotal,
            bytesPerSecond: rate
        )
    }

    public func currentRate(forAbsoluteBytes absoluteBytes: Int64) -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        return computeSmoothedRateLocked(now: ContinuousClock.now, absoluteBytes: max(lastSampleBytes, absoluteBytes))
    }

    private func computeSmoothedRateLocked(now: ContinuousClock.Instant, absoluteBytes: Int64) -> Int64 {
        let sampleElapsed = Self.seconds(from: now - lastSampleTime)
        let deltaBytes = max(0, absoluteBytes - lastSampleBytes)
        if sampleElapsed >= 0.01, deltaBytes > 0 {
            let instantRate = Double(deltaBytes) / sampleElapsed
            smoothedBytesPerSecond = smoothedBytesPerSecond > 0
                ? (0.35 * instantRate) + (0.65 * smoothedBytesPerSecond)
                : instantRate
            lastSampleTime = now
            lastSampleBytes = absoluteBytes
        }

        if smoothedBytesPerSecond > 0 {
            return max(0, Int64(smoothedBytesPerSecond.rounded()))
        }

        let totalElapsed = max(0.001, Self.seconds(from: now - startTime))
        let totalTransferred = max(0, absoluteBytes - initialOffset)
        return totalTransferred > 0 ? Int64((Double(totalTransferred) / totalElapsed).rounded()) : 0
    }

    private static func seconds(from duration: Duration) -> Double {
        Double(duration.components.seconds) + (Double(duration.components.attoseconds) / 1e18)
    }
}
