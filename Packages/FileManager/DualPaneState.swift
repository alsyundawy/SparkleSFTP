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

    public init(allFiles: [RemoteFile] = [], pageSize: Int = 1000) {
        self.pageSize = max(100, pageSize)
        self.allFiles = allFiles
        visibleCount = min(allFiles.count, self.pageSize)
    }

    public var visibleFiles: ArraySlice<RemoteFile> {
        allFiles.prefix(visibleCount)
    }

    public var hasMorePages: Bool {
        visibleCount < allFiles.count
    }

    public mutating func loadNextPage() {
        visibleCount = min(allFiles.count, visibleCount + pageSize)
    }

    public mutating func replaceFiles(_ newFiles: [RemoteFile]) {
        allFiles = newFiles
        visibleCount = min(newFiles.count, pageSize)
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
