import Crypto
import Foundation
import SparkleCore

/// Supported hashing algorithms for integrity checks.
public enum ChecksumAlgorithm: String, Sendable, CaseIterable, Identifiable {
    case sha256
    case sha512
    case sha1
    case md5

    public var id: String {
        rawValue
    }

    public var displayName: String {
        switch self {
        case .sha256: return "SHA-256"
        case .sha512: return "SHA-512"
        case .sha1: return "SHA-1 (Legacy)"
        case .md5: return "MD5 (Legacy)"
        }
    }

    public var expectedHexLength: Int {
        switch self {
        case .md5: return 32
        case .sha1: return 40
        case .sha256: return 64
        case .sha512: return 128
        }
    }

    public var isSecure: Bool {
        self == .sha256 || self == .sha512
    }
}

/// Service computing and verifying streaming cryptographic and legacy checksums.
public enum ChecksumService {
    /// Computes streaming hex digest of local file without loading full file into memory (PERF-002).
    public static func computeDigest(
        of fileURL: URL,
        algorithm: ChecksumAlgorithm = .sha256,
        chunkSize: Int = 1_048_576
    ) async throws -> String {
        try await Task.detached(priority: .utility) {
            let handle = try FileHandle(forReadingFrom: fileURL)
            defer { try? handle.close() }

            switch algorithm {
            case .sha256:
                return try streamSHA256(handle: handle, chunkSize: chunkSize)
            case .sha512:
                return try streamSHA512(handle: handle, chunkSize: chunkSize)
            case .sha1:
                return try streamSHA1(handle: handle, chunkSize: chunkSize)
            case .md5:
                return try streamMD5(handle: handle, chunkSize: chunkSize)
            }
        }.value
    }

    private static func streamSHA256(handle: FileHandle, chunkSize: Int) throws -> String {
        var hasher = SHA256()
        while true {
            try Task.checkCancellation()
            let chunk = try handle.read(upToCount: chunkSize) ?? Data()
            if chunk.isEmpty {
                break
            }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func streamSHA512(handle: FileHandle, chunkSize: Int) throws -> String {
        var hasher = SHA512()
        while true {
            try Task.checkCancellation()
            let chunk = try handle.read(upToCount: chunkSize) ?? Data()
            if chunk.isEmpty {
                break
            }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func streamSHA1(handle: FileHandle, chunkSize: Int) throws -> String {
        var hasher = Insecure.SHA1()
        while true {
            try Task.checkCancellation()
            let chunk = try handle.read(upToCount: chunkSize) ?? Data()
            if chunk.isEmpty {
                break
            }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func streamMD5(handle: FileHandle, chunkSize: Int) throws -> String {
        var hasher = Insecure.MD5()
        while true {
            try Task.checkCancellation()
            let chunk = try handle.read(upToCount: chunkSize) ?? Data()
            if chunk.isEmpty {
                break
            }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Generates agentless remote shell command for non-download checksum calculation.
    public static func remoteShellCommand(for algorithm: ChecksumAlgorithm, remotePath: String) -> String {
        let safePath = remotePath.replacingOccurrences(of: "'", with: "'\\''")
        switch algorithm {
        case .sha256:
            return "sha256sum '\(safePath)' 2>/dev/null || shasum -a 256 '\(safePath)'"
        case .sha512:
            return "sha512sum '\(safePath)' 2>/dev/null || shasum -a 512 '\(safePath)'"
        case .sha1:
            return "sha1sum '\(safePath)' 2>/dev/null || shasum -a 1 '\(safePath)'"
        case .md5:
            return "md5sum '\(safePath)' 2>/dev/null || md5 -q '\(safePath)'"
        }
    }

    /// Extracts hexadecimal digest from raw remote command output.
    public static func extractDigest(from output: String, algorithm: ChecksumAlgorithm) -> String? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = trimmed.components(separatedBy: CharacterSet.whitespacesAndNewlines)
        for token in tokens {
            let lower = token.lowercased()
            if lower.count == algorithm.expectedHexLength,
               lower.allSatisfy({ "0123456789abcdef".contains($0) }) {
                return lower
            }
        }
        return nil
    }
}
