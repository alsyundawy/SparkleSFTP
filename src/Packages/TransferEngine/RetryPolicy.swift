import Foundation
import SparkleCore

/// Actionable decision for retrying a failed transfer item.
public enum RetryDecision: Sendable, Equatable {
    case shouldRetry(delay: TimeInterval, attemptNumber: Int)
    case doNotRetry(reason: String)
}

/// Exponential backoff and jitter policy governing automated transfer retries.
public struct RetryPolicy: Sendable, Equatable {
    public let maxRetries: Int
    public let baseDelay: TimeInterval
    public let maxDelay: TimeInterval
    public let jitterFraction: Double

    public init(
        maxRetries: Int = 0,
        baseDelay: TimeInterval = 1.0,
        maxDelay: TimeInterval = 16.0,
        jitterFraction: Double = 0.25
    ) {
        self.maxRetries = max(0, min(5, maxRetries))
        self.baseDelay = max(0.1, baseDelay)
        self.maxDelay = max(baseDelay, maxDelay)
        self.jitterFraction = max(0.0, min(1.0, jitterFraction))
    }

    /// Evaluates whether an error condition qualifies for retry and computes the appropriate delay.
    public func evaluate(attempt: Int, error: Error, deterministicJitter: Double? = nil) -> RetryDecision {
        guard maxRetries > 0 else {
            return .doNotRetry(reason: "Automated retries disabled")
        }
        guard attempt < maxRetries else {
            return .doNotRetry(reason: "Maximum retry limit reached (\(maxRetries))")
        }

        if let appError = error as? AppError {
            if !appError.isRetryable {
                return .doNotRetry(reason: "Non-retryable application error: \(appError.localizedDescription)")
            }
        }

        let exponentialMultiplier = pow(2.0, Double(attempt))
        let nominalDelay = min(maxDelay, baseDelay * exponentialMultiplier)

        let jitterRatio = deterministicJitter ?? Double.random(in: 0.0 ... jitterFraction)
        let totalDelay = nominalDelay * (1.0 + jitterRatio)

        return .shouldRetry(delay: totalDelay, attemptNumber: attempt + 1)
    }
}
