import Foundation
import SparkleCore

public enum PaneSide: String, Sendable {
    case left
    case right
}

public enum PaneMode: Sendable, Equatable {
    case local(URL)
    case remote(profileID: UUID, path: RemotePath)
}

/// Paginated browser buffer keeping 100K+ directory listings responsive on MainActor (PERF-001).
public struct PaginatedFileWindow: Sendable, Equatable {
    public let pageSize: Int
    public private(set) var allFiles: [RemoteFile]
    public private(set) var visibleCount: Int
    public private(set) var filterQuery: String

    public init(allFiles: [RemoteFile] = [], pageSize: Int = 1000, filterQuery: String = "") {
        self.pageSize = max(100, pageSize)
        self.allFiles = allFiles
        self.filterQuery = filterQuery
        let filtered = Self.applyFilter(allFiles, query: filterQuery)
        visibleCount = min(filtered.count, self.pageSize)
    }

    public var filteredFiles: [RemoteFile] {
        Self.applyFilter(allFiles, query: filterQuery)
    }

    public var visibleFiles: ArraySlice<RemoteFile> {
        filteredFiles.prefix(visibleCount)
    }

    public var hasMorePages: Bool {
        visibleCount < filteredFiles.count
    }

    public mutating func loadNextPage() {
        visibleCount = min(filteredFiles.count, visibleCount + pageSize)
    }

    public mutating func replaceFiles(_ newFiles: [RemoteFile]) {
        allFiles = newFiles
        visibleCount = min(filteredFiles.count, pageSize)
    }

    public mutating func setFilter(_ query: String) {
        filterQuery = query
        visibleCount = min(filteredFiles.count, pageSize)
    }

    private static func applyFilter(_ files: [RemoteFile], query: String) -> [RemoteFile] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return files }
        if trimmed.hasPrefix("*.") {
            let ext = String(trimmed.dropFirst(2))
            return files.filter { ($0.name as NSString).pathExtension.lowercased() == ext }
        }
        if trimmed == ".*" || trimmed == "hidden" {
            return files.filter { $0.name.hasPrefix(".") }
        }
        return files.filter { $0.name.lowercased().contains(trimmed) }
    }
}

/// Manages Back/Forward/Up navigation history for a single commander pane.
public struct PaneNavigationHistory: Sendable, Equatable {
    private var backStack: [String] = []
    private var forwardStack: [String] = []
    public private(set) var currentPath: String

    public init(initialPath: String) {
        currentPath = initialPath
    }

    public var canGoBack: Bool {
        !backStack.isEmpty
    }

    public var canGoForward: Bool {
        !forwardStack.isEmpty
    }

    public mutating func navigate(to newPath: String) {
        guard newPath != currentPath else { return }
        backStack.append(currentPath)
        currentPath = newPath
        forwardStack.removeAll()
    }

    @discardableResult
    public mutating func goBack() -> String? {
        guard let prev = backStack.popLast() else { return nil }
        forwardStack.append(currentPath)
        currentPath = prev
        return prev
    }

    @discardableResult
    public mutating func goForward() -> String? {
        guard let next = forwardStack.popLast() else { return nil }
        backStack.append(currentPath)
        currentPath = next
        return next
    }
}
