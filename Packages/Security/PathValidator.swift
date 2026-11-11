import Foundation
import SparkleCore

/// Enforces CWE-22 path canonicalization and CWE-59 symlink boundary checks before reads/writes.
public enum PathValidator {
    /// Canonicalizes an untrusted remote path relative to `baseDir`, rejecting escapes and NUL bytes.
    public static func canonicalizeRemote(_ rawPath: String, relativeTo baseDir: RemotePath) throws -> RemotePath {
        if rawPath.contains("\0") {
            throw AppError.pathTraversal(attempted: rawPath)
        }

        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw AppError.pathTraversal(attempted: rawPath)
        }

        let combined: String = if trimmed.hasPrefix("/") {
            trimmed
        } else if baseDir.isRoot {
            "/" + trimmed
        } else {
            baseDir.rawValue + "/" + trimmed
        }

        // Check raw traversal segments explicitly before normalization clamps at root.
        let rawSegments = trimmed.split(separator: "/", omittingEmptySubsequences: true)
        if rawSegments.contains(".."), !trimmed.hasPrefix("/") {
            let resolved = resolveDotsCheckingEscape(base: baseDir.rawValue, segments: rawSegments)
            guard let safeResolved = resolved else {
                throw AppError.pathTraversal(attempted: rawPath)
            }
            return RemotePath(rawValue: safeResolved)
        }

        let normalized = RemotePath(rawValue: combined)
        if !baseDir.isRoot {
            let basePrefix = baseDir.rawValue + "/"
            guard normalized.rawValue == baseDir.rawValue || normalized.rawValue.hasPrefix(basePrefix) else {
                throw AppError.pathTraversal(attempted: rawPath)
            }
        }
        return normalized
    }

    /// Validates a local destination URL for downloading a remote item, rejecting CWE-22 and CWE-59 escapes.
    public static func safeLocalDestination(
        filename: String,
        baseDirectory: URL,
        symlinkTarget: String? = nil
    ) throws -> URL {
        if filename.isEmpty || filename == "." || filename == ".." ||
            filename.contains("/") || filename.contains("\0") {
            throw AppError.pathTraversal(attempted: filename)
        }

        if let target = symlinkTarget {
            let segments = target.split(separator: "/", omittingEmptySubsequences: true)
            if target.hasPrefix("/") || segments.contains("..") {
                throw AppError.maliciousSymlink(target: target)
            }
        }

        let standardizedBase = baseDirectory.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = standardizedBase.appendingPathComponent(filename, isDirectory: false)
        let standardizedCandidate = candidate.standardizedFileURL

        let basePath = standardizedBase.path.hasSuffix("/") ? standardizedBase.path : standardizedBase.path + "/"
        guard standardizedCandidate.path.hasPrefix(basePath) else {
            throw AppError.symlinkTraversal(destination: standardizedCandidate.path)
        }

        // Reject pre-existing symlinks at destination path to prevent overwriting outside baseDirectory (CWE-59).
        if (try? FileManager.default.destinationOfSymbolicLink(atPath: standardizedCandidate.path)) != nil {
            throw AppError.symlinkTraversal(destination: standardizedCandidate.path)
        }

        // Ensure no intermediate symlink in local path escapes baseDirectory.
        let resolvedParent = standardizedCandidate.deletingLastPathComponent().resolvingSymlinksInPath()
        guard resolvedParent.path == standardizedBase.path || resolvedParent.path.hasPrefix(basePath) else {
            throw AppError.symlinkTraversal(destination: resolvedParent.path)
        }

        return standardizedCandidate
    }

    private static func resolveDotsCheckingEscape(base: String, segments: [Substring]) -> String? {
        var stack = base.split(separator: "/", omittingEmptySubsequences: true)
        let minDepth = stack.count
        for segment in segments {
            if segment == "." {
                continue
            }
            if segment == ".." {
                if stack.count <= minDepth {
                    return nil
                }
                stack.removeLast()
            } else {
                stack.append(segment)
            }
        }
        return stack.isEmpty ? "/" : "/" + stack.joined(separator: "/")
    }
}
