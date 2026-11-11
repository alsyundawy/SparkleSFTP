import Crypto
import Foundation
import SparkleCore

/// Streaming off-MainActor SHA-256 verification for multi-GB transfers (PERF-002).
public enum SHA256Verifier {
    public static func computeHexDigest(of fileURL: URL, chunkSize: Int = 1_048_576) async throws -> String {
        try await Task.detached(priority: .utility) {
            let handle = try FileHandle(forReadingFrom: fileURL)
            defer { try? handle.close() }

            var hasher = SHA256()
            while true {
                try Task.checkCancellation()
                let chunk = try handle.read(upToCount: chunkSize) ?? Data()
                if chunk.isEmpty {
                    break
                }
                hasher.update(data: chunk)
            }
            let digest = hasher.finalize()
            return digest.map { String(format: "%02x", $0) }.joined()
        }.value
    }

    public static func verify(fileURL: URL, expectedHex: String) async throws {
        let actual = try await computeHexDigest(of: fileURL)
        let normalizedExpected = expectedHex.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard actual == normalizedExpected else {
            throw AppError.checksumMismatch(expected: normalizedExpected, actual: actual)
        }
    }
}
