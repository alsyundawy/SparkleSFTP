import Foundation
import SparkleCore

/// Manages directory bookmarks, 20-item path histories, and synchronized browsing (v0.5.0).
@MainActor
public final class BookmarkManager: ObservableObject {
    public static let shared = BookmarkManager()

    public static let maxHistoryCount = 20

    private static let bookmarksKey = "sparkle.bookmarks.v1"
    private static let localHistoryKey = "sparkle.localPathHistory.v1"
    private static let remoteHistoriesKey = "sparkle.remotePathHistories.v1"
    private static let syncBrowsingKey = "sparkle.syncBrowsing.v1"

    @Published public private(set) var bookmarks: [BookmarkItem] = []
    @Published public private(set) var localHistory: [PathHistoryItem] = []
    @Published public private(set) var remoteHistories: [String: [PathHistoryItem]] = [:]

    private let userDefaults: UserDefaults

    @Published public var isSynchronizedBrowsingEnabled: Bool {
        didSet {
            userDefaults.set(isSynchronizedBrowsingEnabled, forKey: Self.syncBrowsingKey)
        }
    }

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        isSynchronizedBrowsingEnabled = userDefaults.bool(forKey: Self.syncBrowsingKey)
        loadFromStorage()
    }

    // MARK: - Bookmarks Management

    @discardableResult
    public func addBookmark(
        name: String,
        path: String,
        isRemote: Bool,
        hostIdentifier: String? = nil,
        iconName: String? = nil
    ) -> BookmarkItem {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let lastSegment = URL(fileURLWithPath: path).lastPathComponent
        let fallbackName = lastSegment.isEmpty ? path : lastSegment
        let finalName = trimmedName.isEmpty ? fallbackName : trimmedName
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)

        let bookmark = BookmarkItem(
            name: finalName,
            path: trimmedPath,
            hostIdentifier: hostIdentifier,
            isRemote: isRemote,
            iconName: iconName
        )
        bookmarks.insert(bookmark, at: 0)
        saveBookmarks()
        return bookmark
    }

    public func removeBookmark(id: UUID) {
        bookmarks.removeAll { $0.id == id }
        saveBookmarks()
    }

    public func updateBookmark(_ item: BookmarkItem) {
        if let index = bookmarks.firstIndex(where: { $0.id == item.id }) {
            bookmarks[index] = item
            saveBookmarks()
        }
    }

    public func bookmarks(forHost hostIdentifier: String?, isRemote: Bool) -> [BookmarkItem] {
        bookmarks.filter { item in
            if isRemote {
                guard item.isRemote else { return false }
                guard let host = hostIdentifier else { return true }
                return item.hostIdentifier == nil || item.hostIdentifier == host
            } else {
                return !item.isRemote
            }
        }
    }

    // MARK: - Path History (20-item ring buffer)

    public func recordPath(_ path: String, isRemote: Bool, hostIdentifier: String? = nil) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let item = PathHistoryItem(path: trimmed, isRemote: isRemote, hostIdentifier: hostIdentifier)

        if isRemote {
            let key = hostIdentifier ?? "default"
            var list = remoteHistories[key] ?? []
            list.removeAll { $0.path == trimmed }
            list.insert(item, at: 0)
            if list.count > Self.maxHistoryCount {
                list = Array(list.prefix(Self.maxHistoryCount))
            }
            remoteHistories[key] = list
            saveRemoteHistories()
        } else {
            var list = localHistory
            list.removeAll { $0.path == trimmed }
            list.insert(item, at: 0)
            if list.count > Self.maxHistoryCount {
                list = Array(list.prefix(Self.maxHistoryCount))
            }
            localHistory = list
            saveLocalHistory()
        }
    }

    public func recentPaths(isRemote: Bool, hostIdentifier: String? = nil) -> [PathHistoryItem] {
        if isRemote {
            let key = hostIdentifier ?? "default"
            return remoteHistories[key] ?? []
        } else {
            return localHistory
        }
    }

    public func clearHistory(isRemote: Bool, hostIdentifier: String? = nil) {
        if isRemote {
            let key = hostIdentifier ?? "default"
            remoteHistories.removeValue(forKey: key)
            saveRemoteHistories()
        } else {
            localHistory.removeAll()
            saveLocalHistory()
        }
    }

    // MARK: - Synchronized Browsing Helpers

    /// Computes the synchronized destination path in the opposite pane if navigation occurs.
    public func computeSynchronizedPath(
        from oldPath: String,
        to newPath: String,
        currentOppositePath: String
    ) -> String? {
        guard isSynchronizedBrowsingEnabled else { return nil }

        let cleanOld = oldPath.hasSuffix("/") && oldPath.count > 1 ? String(oldPath.dropLast()) : oldPath
        let cleanNew = newPath.hasSuffix("/") && newPath.count > 1 ? String(newPath.dropLast()) : newPath
        let cleanOpp = currentOppositePath.hasSuffix("/") && currentOppositePath.count > 1
            ? String(currentOppositePath.dropLast())
            : currentOppositePath

        // If navigated down one level (e.g. /a -> /a/b)
        if cleanNew.hasPrefix(cleanOld + "/") {
            let relativeSub = String(cleanNew.dropFirst(cleanOld.count + 1))
            return cleanOpp == "/" ? "/" + relativeSub : cleanOpp + "/" + relativeSub
        }

        // If navigated up one level (parent directory)
        if cleanOld.hasPrefix(cleanNew + "/") {
            let parent = (cleanOpp as NSString).deletingLastPathComponent
            return parent.isEmpty ? "/" : parent
        }

        return nil
    }

    // MARK: - Persistence Internals

    private func saveBookmarks() {
        if let data = try? JSONEncoder().encode(bookmarks) {
            userDefaults.set(data, forKey: Self.bookmarksKey)
        }
    }

    private func saveLocalHistory() {
        if let data = try? JSONEncoder().encode(localHistory) {
            userDefaults.set(data, forKey: Self.localHistoryKey)
        }
    }

    private func saveRemoteHistories() {
        if let data = try? JSONEncoder().encode(remoteHistories) {
            userDefaults.set(data, forKey: Self.remoteHistoriesKey)
        }
    }

    private func loadFromStorage() {
        if let data = userDefaults.data(forKey: Self.bookmarksKey),
           let decoded = try? JSONDecoder().decode([BookmarkItem].self, from: data) {
            bookmarks = decoded
        }

        if let data = userDefaults.data(forKey: Self.localHistoryKey),
           let decoded = try? JSONDecoder().decode([PathHistoryItem].self, from: data) {
            localHistory = decoded
        }

        if let data = userDefaults.data(forKey: Self.remoteHistoriesKey),
           let decoded = try? JSONDecoder().decode([String: [PathHistoryItem]].self, from: data) {
            remoteHistories = decoded
        }
    }
}
