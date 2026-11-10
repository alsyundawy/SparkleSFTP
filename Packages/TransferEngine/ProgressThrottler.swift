import Foundation
import SparkleCore

/// Throttles high-frequency byte progress events to max 10 Hz (100ms) with bounded buffering (MEM-003, PERF-004).
public actor ProgressThrottler {
    private var lastEmitTimes: [UUID: ContinuousClock.Instant] = [:]
    private let minimumInterval: Duration

    public init(minimumInterval: Duration = .milliseconds(100)) {
        self.minimumInterval = minimumInterval
    }

    public func shouldEmit(for taskID: UUID, force: Bool = false) -> Bool {
        if force {
            lastEmitTimes[taskID] = ContinuousClock.now
            return true
        }
        let now = ContinuousClock.now
        if let last = lastEmitTimes[taskID], now - last < minimumInterval {
            return false
        }
        lastEmitTimes[taskID] = now
        return true
    }

    public func clear(taskID: UUID) {
        lastEmitTimes.removeValue(forKey: taskID)
    }
}
