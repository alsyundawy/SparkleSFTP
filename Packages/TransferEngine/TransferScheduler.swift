import Foundation
import SparkleCore

/// Enforces global concurrency limits, per-host concurrency limits (SCALE-001), and priority admission.
public actor TransferScheduler {
    public private(set) var maxGlobalConcurrent: Int
    public private(set) var maxPerHostConcurrent: Int

    private var pendingQueue: [TransferTaskMetadata] = []
    private var activePerHost: [String: Int] = [:]

    public init(maxGlobalConcurrent: Int = 4, maxPerHostConcurrent: Int = 3) {
        self.maxGlobalConcurrent = min(16, max(1, maxGlobalConcurrent))
        self.maxPerHostConcurrent = min(8, max(1, maxPerHostConcurrent))
    }

    public func updateLimits(maxGlobalConcurrent: Int, maxPerHostConcurrent: Int) {
        self.maxGlobalConcurrent = min(16, max(1, maxGlobalConcurrent))
        self.maxPerHostConcurrent = min(8, max(1, maxPerHostConcurrent))
    }

    public var totalActiveCount: Int {
        activePerHost.values.reduce(0, +)
    }

    public func activeCount(forHost host: String) -> Int {
        activePerHost[host, default: 0]
    }

    public func enqueue(_ metadata: TransferTaskMetadata) {
        guard !pendingQueue.contains(where: { $0.id == metadata.id }) else { return }
        pendingQueue.append(metadata)
        pendingQueue.sort { lhs, rhs in
            if lhs.priority != rhs.priority {
                return lhs.priority > rhs.priority
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    public func removePending(id: UUID) {
        pendingQueue.removeAll { $0.id == id }
    }

    public func canStart(_ metadata: TransferTaskMetadata) -> Bool {
        let host = metadata.targetHost
        let hostActive = activePerHost[host, default: 0]
        return totalActiveCount < maxGlobalConcurrent && hostActive < maxPerHostConcurrent
    }

    public func nextAdmissibleTask() -> TransferTaskMetadata? {
        guard totalActiveCount < maxGlobalConcurrent else { return nil }
        for (index, candidate) in pendingQueue.enumerated() where canStart(candidate) {
            pendingQueue.remove(at: index)
            let host = candidate.targetHost
            activePerHost[host, default: 0] += 1
            return candidate
        }
        return nil
    }

    public func releaseSlot(forHost host: String) {
        let current = activePerHost[host, default: 0]
        if current <= 1 {
            activePerHost.removeValue(forKey: host)
        } else {
            activePerHost[host] = current - 1
        }
    }
}
