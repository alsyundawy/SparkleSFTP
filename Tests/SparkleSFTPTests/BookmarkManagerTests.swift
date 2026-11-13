import Foundation
@testable import SparkleCore
@testable import SparkleFeatures
import Testing

@Suite("Bookmark & Path History Manager Tests")
struct BookmarkManagerTests {
    private func makeIsolatedDefaults() -> UserDefaults {
        let suiteName = "test.sparkle.bookmarks.\(UUID().uuidString)"
        return UserDefaults(suiteName: suiteName) ?? .standard
    }

    @Test("Adding and deleting bookmarks updates state and persists across reloads")
    @MainActor
    func addAndRemoveBookmarks() {
        let testDefaults = makeIsolatedDefaults()
        let manager = BookmarkManager(userDefaults: testDefaults)

        #expect(manager.bookmarks.isEmpty)

        let remoteBookmark = manager.addBookmark(
            name: "Web Root",
            path: "/var/www/html",
            isRemote: true,
            hostIdentifier: "prod.example.com"
        )
        let localBookmark = manager.addBookmark(
            name: "Local Downloads",
            path: "/Users/alice/Downloads",
            isRemote: false
        )

        #expect(manager.bookmarks.count == 2)
        #expect(manager.bookmarks.first?.id == localBookmark.id)

        let remoteForProd = manager.bookmarks(forHost: "prod.example.com", isRemote: true)
        #expect(remoteForProd.count == 1)
        #expect(remoteForProd.first?.name == "Web Root")

        let localBookmarks = manager.bookmarks(forHost: nil, isRemote: false)
        #expect(localBookmarks.count == 1)
        #expect(localBookmarks.first?.path == "/Users/alice/Downloads")

        // Reload manager from same UserDefaults to verify persistence
        let reloaded = BookmarkManager(userDefaults: testDefaults)
        #expect(reloaded.bookmarks.count == 2)
        #expect(reloaded.bookmarks.contains(where: { $0.id == remoteBookmark.id }))

        // Remove bookmark
        reloaded.removeBookmark(id: remoteBookmark.id)
        #expect(reloaded.bookmarks.count == 1)
        #expect(!reloaded.bookmarks.contains(where: { $0.id == remoteBookmark.id }))
    }

    @Test("Path history enforces 20-item ring buffer and deduplication")
    @MainActor
    func pathHistoryRingBuffer() {
        let testDefaults = makeIsolatedDefaults()
        let manager = BookmarkManager(userDefaults: testDefaults)

        for index in 1 ... 25 {
            manager.recordPath("/var/log/app_\(index)", isRemote: true, hostIdentifier: "server-a")
        }

        let history = manager.recentPaths(isRemote: true, hostIdentifier: "server-a")
        #expect(history.count == BookmarkManager.maxHistoryCount)
        #expect(history.first?.path == "/var/log/app_25")
        #expect(history.last?.path == "/var/log/app_6")

        // Deduplication test
        manager.recordPath("/var/log/app_25", isRemote: true, hostIdentifier: "server-a")
        let deduped = manager.recentPaths(isRemote: true, hostIdentifier: "server-a")
        #expect(deduped.count == BookmarkManager.maxHistoryCount)
        #expect(deduped.first?.path == "/var/log/app_25")

        // Clear history
        manager.clearHistory(isRemote: true, hostIdentifier: "server-a")
        #expect(manager.recentPaths(isRemote: true, hostIdentifier: "server-a").isEmpty)
    }

    @Test("Synchronized browsing computes matching child and parent paths")
    @MainActor
    func synchronizedBrowsingCalculations() {
        let testDefaults = makeIsolatedDefaults()
        let manager = BookmarkManager(userDefaults: testDefaults)
        manager.isSynchronizedBrowsingEnabled = true

        // Moving into child directory
        let syncChild = manager.computeSynchronizedPath(
            from: "/var/www",
            to: "/var/www/public_html",
            currentOppositePath: "/Users/dev/project"
        )
        #expect(syncChild == "/Users/dev/project/public_html")

        // Moving up to parent directory
        let syncParent = manager.computeSynchronizedPath(
            from: "/var/www/public_html",
            to: "/var/www",
            currentOppositePath: "/Users/dev/project/public_html"
        )
        #expect(syncParent == "/Users/dev/project")

        // Disabled synchronized browsing returns nil
        manager.isSynchronizedBrowsingEnabled = false
        let syncDisabled = manager.computeSynchronizedPath(
            from: "/var/www",
            to: "/var/www/public_html",
            currentOppositePath: "/Users/dev/project"
        )
        #expect(syncDisabled == nil)
    }
}
