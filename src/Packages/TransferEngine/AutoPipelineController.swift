import Foundation

/// Adaptive transfer pipeline depth coordinator matching FileZilla 3.72 auto-tuning specifications.
public final class AutoPipelineController:
    @unchecked Sendable { // JUSTIFICATION: Synchronized via internal NSLock.
    public static let defaultMinDepth = 1
    public static let defaultMaxDepth = 16

    private let lock = NSLock()
    private let minDepth: Int
    private let maxDepth: Int
    private var currentDepth: Int
    private var lastAdjustmentTime: TimeInterval
    private var successfulBytesSinceAdjustment: Int64 = 0
    private let timeProvider: @Sendable () -> TimeInterval

    public init(
        initialDepth: Int = 4,
        minDepth: Int = defaultMinDepth,
        maxDepth: Int = defaultMaxDepth,
        timeProvider: @escaping @Sendable () -> TimeInterval = { Date().timeIntervalSinceReferenceDate }
    ) {
        self.minDepth = minDepth
        self.maxDepth = maxDepth
        currentDepth = max(minDepth, min(maxDepth, initialDepth))
        self.timeProvider = timeProvider
        lastAdjustmentTime = timeProvider()
    }

    /// Returns current computed pipeline depth.
    public var depth: Int {
        lock.lock()
        defer { lock.unlock() }
        return currentDepth
    }

    /// Records successful transfer chunk completion, evaluating upward adaptation.
    public func recordSuccess(bytes: Int, inFlightFraction: Double) {
        lock.lock()
        defer { lock.unlock() }
        successfulBytesSinceAdjustment += Int64(bytes)
        let now = timeProvider()
        let elapsed = now - lastAdjustmentTime

        // If utilization >= 80% sustained for >= 2.0s, adaptively widen pipeline window
        if elapsed >= 2.0, inFlightFraction >= 0.8 {
            currentDepth = min(maxDepth, currentDepth + 2)
            lastAdjustmentTime = now
            successfulBytesSinceAdjustment = 0
        }
    }

    /// Records transfer stall, throttling pipeline depth by 50% to mitigate network congestion.
    public func recordStallOrBackpressure() {
        lock.lock()
        defer { lock.unlock() }
        currentDepth = max(minDepth, currentDepth / 2)
        lastAdjustmentTime = timeProvider()
        successfulBytesSinceAdjustment = 0
    }

    /// Resets pipeline depth back to initial baseline.
    public func reset(to initialDepth: Int = 4) {
        lock.lock()
        defer { lock.unlock() }
        currentDepth = max(minDepth, min(maxDepth, initialDepth))
        lastAdjustmentTime = timeProvider()
        successfulBytesSinceAdjustment = 0
    }
}
