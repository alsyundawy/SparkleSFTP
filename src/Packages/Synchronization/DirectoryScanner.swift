import Crypto
import Foundation
import SparkleCore
import SparkleSecurity

public struct ScannedFileEntry: Sendable, Equatable {
    public let relativePath: String
    public let size: Int64
    public let modificationTime: Date?
    public let isDirectory: Bool
    public let sha256: String?

    public init(
        relativePath: String,
        size: Int64,
        modificationTime: Date?,
        isDirectory: Bool,
        sha256: String? = nil
    ) {
        self.relativePath = relativePath
        self.size = size
        self.modificationTime = modificationTime
        self.isDirectory = isDirectory
        self.sha256 = sha256
    }
}

/// Async, cancel-safe directory snapshot scanner with circular symlink loop protection (LOG-005).
public enum DirectoryScanner {
    private struct LocalWalkContext {
        let exclusionGlobs: [String]
        let includeSHA256: Bool
    }

    private struct RemoteWalkContext {
        let remoteFS: any RemoteFileSystem
        let exclusionGlobs: [String]
    }

    public static func scanLocal(
        rootURL: URL,
        exclusionGlobs: [String] = [".git", ".DS_Store"],
        includeSHA256: Bool = false
    ) async throws -> [ScannedFileEntry] {
        let resolvedRoot = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        var visitedPaths: Set<String> = [resolvedRoot.path]
        var results: [ScannedFileEntry] = []
        let context = LocalWalkContext(exclusionGlobs: exclusionGlobs, includeSHA256: includeSHA256)
        try await walkLocal(
            currentURL: resolvedRoot,
            relativePrefix: "",
            context: context,
            visitedPaths: &visitedPaths,
            results: &results
        )
        return results
    }

    public static func scanRemote(
        rootPath: RemotePath,
        remoteFS: any RemoteFileSystem,
        exclusionGlobs: [String] = [".git", ".DS_Store"]
    ) async throws -> [ScannedFileEntry] {
        var visitedTargets: Set<String> = [rootPath.rawValue]
        var results: [ScannedFileEntry] = []
        let context = RemoteWalkContext(remoteFS: remoteFS, exclusionGlobs: exclusionGlobs)
        try await walkRemote(
            currentPath: rootPath,
            relativePrefix: "",
            context: context,
            visitedTargets: &visitedTargets,
            results: &results
        )
        return results
    }

    private static func walkLocal(
        currentURL: URL,
        relativePrefix: String,
        context: LocalWalkContext,
        visitedPaths: inout Set<String>,
        results: inout [ScannedFileEntry]
    ) async throws {
        try Task.checkCancellation()
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
        let items = try FileManager.default.contentsOfDirectory(at: currentURL, includingPropertiesForKeys: keys)

        for item in items {
            try Task.checkCancellation()
            try await processLocalItem(
                item,
                relativePrefix: relativePrefix,
                context: context,
                visitedPaths: &visitedPaths,
                results: &results
            )
        }
    }

    private static func processLocalItem(
        _ item: URL,
        relativePrefix: String,
        context: LocalWalkContext,
        visitedPaths: inout Set<String>,
        results: inout [ScannedFileEntry]
    ) async throws {
        let name = item.lastPathComponent
        guard !isExcluded(name: name, patterns: context.exclusionGlobs) else { return }

        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
        let values = try item.resourceValues(forKeys: keys)
        let isLink = values.isSymbolicLink ?? false
        let isDir = values.isDirectory ?? false
        let relPath = relativePrefix.isEmpty ? name : "\(relativePrefix)/\(name)"

        if isLink || isDir {
            let realPath = item.resolvingSymlinksInPath().path
            guard !visitedPaths.contains(realPath) else { return }
            visitedPaths.insert(realPath)
        }

        if isDir {
            results.append(
                ScannedFileEntry(
                    relativePath: relPath,
                    size: 0,
                    modificationTime: values.contentModificationDate,
                    isDirectory: true
                )
            )
            try await walkLocal(
                currentURL: item,
                relativePrefix: relPath,
                context: context,
                visitedPaths: &visitedPaths,
                results: &results
            )
        } else {
            let size = Int64(values.fileSize ?? 0)
            let hash: String? = await context.includeSHA256 ? (try? computeSHA256(url: item)) : nil
            results.append(
                ScannedFileEntry(
                    relativePath: relPath,
                    size: size,
                    modificationTime: values.contentModificationDate,
                    isDirectory: false,
                    sha256: hash
                )
            )
        }
    }

    private static func walkRemote(
        currentPath: RemotePath,
        relativePrefix: String,
        context: RemoteWalkContext,
        visitedTargets: inout Set<String>,
        results: inout [ScannedFileEntry]
    ) async throws {
        try Task.checkCancellation()
        let entries = try await context.remoteFS.listDirectory(at: currentPath)

        for entry in entries {
            try Task.checkCancellation()
            if isExcluded(name: entry.name, patterns: context.exclusionGlobs) {
                continue
            }
            let relPath = relativePrefix.isEmpty ? entry.name : "\(relativePrefix)/\(entry.name)"

            if entry.isSymlink {
                guard let resolved = try? await context.remoteFS.resolveSymlink(at: entry.path),
                      !visitedTargets.contains(resolved.rawValue)
                else {
                    continue // Skip dangling or circular symlink targets safely (LOG-005).
                }
                visitedTargets.insert(resolved.rawValue)
            }

            if entry.isDirectory {
                if !entry.isSymlink {
                    guard !visitedTargets.contains(entry.path.rawValue) else { continue }
                    visitedTargets.insert(entry.path.rawValue)
                }
                results.append(
                    ScannedFileEntry(
                        relativePath: relPath,
                        size: 0,
                        modificationTime: entry.modificationTime,
                        isDirectory: true
                    )
                )
                try await walkRemote(
                    currentPath: entry.path,
                    relativePrefix: relPath,
                    context: context,
                    visitedTargets: &visitedTargets,
                    results: &results
                )
            } else {
                results.append(
                    ScannedFileEntry(
                        relativePath: relPath,
                        size: entry.size,
                        modificationTime: entry.modificationTime,
                        isDirectory: false
                    )
                )
            }
        }
    }

    public static func isExcluded(name: String, patterns: [String]) -> Bool {
        for pattern in patterns {
            if pattern == name {
                return true
            }
            if pattern.hasPrefix("*."), name.hasSuffix(String(pattern.dropFirst())) {
                return true
            }
        }
        return false
    }

    private static func computeSHA256(url: URL) async throws -> String {
        try await Task.detached(priority: .utility) {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }

            var hasher = SHA256()
            while true {
                try Task.checkCancellation()
                let chunk = try handle.read(upToCount: 1_048_576) ?? Data()
                if chunk.isEmpty {
                    break
                }
                hasher.update(data: chunk)
            }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        }.value
    }
}
