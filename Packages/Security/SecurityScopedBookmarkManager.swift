import Foundation
import SparkleCore

/// Manages security-scoped bookmarks and isolated 0700 temporary staging directories.
public enum SecurityScopedBookmarkManager {
    public static func createBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    public static func resolveBookmark(_ data: Data) throws -> URL {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return url
    }

    public static func withScopedAccess<T>(to url: URL, perform: (URL) throws -> T) throws -> T {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try perform(url)
    }
}

public enum SecureTempDirectory {
    public static func createIsolatedWorkingDirectory(prefix: String = "SparkleSFTP") throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: base,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return base
    }
}
