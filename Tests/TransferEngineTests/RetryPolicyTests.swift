import Foundation
import SparkleCore
@testable import SparkleTransferEngine
import Testing

@Suite("Transfer Retry Policy & Backoff Tests")
struct RetryPolicyTests {
    @Test("Retry policy evaluates exponential backoff with zero jitter")
    func exponentialBackoffEvaluation() {
        let policy = RetryPolicy(maxRetries: 3, baseDelay: 1.0, maxDelay: 16.0, jitterFraction: 0.0)
        let transientError = AppError.channelStalled(reason: "Socket closed abruptly")

        let decision0 = policy.evaluate(attempt: 0, error: transientError, deterministicJitter: 0.0)
        #expect(decision0 == .shouldRetry(delay: 1.0, attemptNumber: 1))

        let decision1 = policy.evaluate(attempt: 1, error: transientError, deterministicJitter: 0.0)
        #expect(decision1 == .shouldRetry(delay: 2.0, attemptNumber: 2))

        let decision2 = policy.evaluate(attempt: 2, error: transientError, deterministicJitter: 0.0)
        #expect(decision2 == .shouldRetry(delay: 4.0, attemptNumber: 3))

        let decision3 = policy.evaluate(attempt: 3, error: transientError, deterministicJitter: 0.0)
        #expect(decision3 == .doNotRetry(reason: "Maximum retry limit reached (3)"))
    }

    @Test("Security, authentication, and permission errors are rejected from retry")
    func nonRetryableErrors() {
        let policy = RetryPolicy(maxRetries: 3)
        let authError = AppError.authenticationFailed(method: .password)
        let permError = AppError.permissionDenied(path: "/root/secret")
        let traversalError = AppError.pathTraversal(attempted: "../etc/passwd")

        #expect(policy.evaluate(attempt: 0, error: authError) != .shouldRetry(delay: 1.0, attemptNumber: 1))
        #expect(policy.evaluate(attempt: 0, error: permError) != .shouldRetry(delay: 1.0, attemptNumber: 1))
        #expect(policy.evaluate(attempt: 0, error: traversalError) != .shouldRetry(delay: 1.0, attemptNumber: 1))
    }
}
