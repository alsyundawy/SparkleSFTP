import Foundation
@testable import SparkleTransferEngine
import Testing

@Suite("Transfer Rate Limiter & Token Bucket Tests")
struct TransferRateLimiterTests {
    @Test("Unlimited mode (limit = 0) returns immediately without delay")
    func unlimitedMode() async throws {
        let limiter = TransferRateLimiter(limitKBps: 0)
        #expect(limiter.currentLimitKBps == 0)
        try await limiter.consume(bytes: 1_000_000)
    }

    @Test("Rate limiter respects dynamically updated bandwidth limits")
    func dynamicLimitUpdate() {
        let limiter = TransferRateLimiter(limitKBps: 512)
        #expect(limiter.currentLimitKBps == 512)

        limiter.setLimit(kbps: 1024)
        #expect(limiter.currentLimitKBps == 1024)

        limiter.setLimit(kbps: 0)
        #expect(limiter.currentLimitKBps == 0)
    }
}
