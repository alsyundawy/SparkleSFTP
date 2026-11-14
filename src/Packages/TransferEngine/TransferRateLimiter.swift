import Foundation

/// Token-bucket bandwidth limiter regulating upload and download throughput.
public final class TransferRateLimiter: @unchecked Sendable { // JUSTIFICATION: Protected via internal NSLock.
    private let lock = NSLock()
    private var limitKBps: Int
    private var availableTokens: Double
    private var lastRefillTime: TimeInterval
    private let timeProvider: @Sendable () -> TimeInterval

    public init(
        limitKBps: Int = 0,
        timeProvider: @escaping @Sendable () -> TimeInterval = { Date().timeIntervalSinceReferenceDate }
    ) {
        self.limitKBps = max(0, limitKBps)
        self.timeProvider = timeProvider
        let now = timeProvider()
        lastRefillTime = now
        let bytesPerSec = Double(max(0, limitKBps)) * 1024.0
        availableTokens = bytesPerSec
    }

    /// Dynamically updates the bandwidth limit in KB/s (0 = unlimited).
    public func setLimit(kbps: Int) {
        lock.lock()
        defer { lock.unlock() }
        limitKBps = max(0, kbps)
        let bytesPerSec = Double(limitKBps) * 1024.0
        availableTokens = min(availableTokens, bytesPerSec)
    }

    /// Returns the active bandwidth limit in KB/s.
    public var currentLimitKBps: Int {
        lock.lock()
        defer { lock.unlock() }
        return limitKBps
    }

    /// Consumes tokens for a transfer block, sleeping asynchronously if bucket is exhausted.
    public func consume(bytes: Int) async throws {
        guard bytes > 0 else { return }

        while true {
            try Task.checkCancellation()

            let waitDuration: TimeInterval? = lock.withLock {
                guard limitKBps > 0 else { return nil }

                let now = timeProvider()
                let elapsed = max(0, now - lastRefillTime)
                lastRefillTime = now

                let bytesPerSec = Double(limitKBps) * 1024.0
                availableTokens = min(bytesPerSec, availableTokens + (elapsed * bytesPerSec))

                if availableTokens >= Double(bytes) {
                    availableTokens -= Double(bytes)
                    return nil
                } else {
                    let needed = Double(bytes) - availableTokens
                    return needed / bytesPerSec
                }
            }

            guard let duration = waitDuration, duration > 0 else {
                return
            }

            let nanoseconds = UInt64(min(duration, 1.0) * 1_000_000_000)
            try await Task.sleep(nanoseconds: nanoseconds)
        }
    }
}
