import Foundation
import SparkleCore
@testable import SparkleSynchronization
import Testing

@Suite("SparkleSynchronization Tests")
struct SynchronizationTests {
    @Test("SyncPlanner creates pure dry-run actions and enforces 60s expiry (LOG-003)")
    func syncPlannerAndExpiry() {
        let baseTime = Date(timeIntervalSince1970: 1_700_000_000)
        let source = [
            ScannedFileEntry(
                relativePath: "index.html",
                size: 200,
                modificationTime: baseTime.addingTimeInterval(10),
                isDirectory: false
            ),
            ScannedFileEntry(relativePath: "new.js", size: 50, modificationTime: baseTime, isDirectory: false)
        ]
        let destination = [
            ScannedFileEntry(relativePath: "index.html", size: 150, modificationTime: baseTime, isDirectory: false),
            ScannedFileEntry(relativePath: "old.css", size: 30, modificationTime: baseTime, isDirectory: false)
        ]

        let plan = SyncPlanner.buildPlan(
            source: source,
            destination: destination,
            deleteExtras: true,
            ttlSeconds: 60,
            now: baseTime
        )
        #expect(plan.createActions.map(\.relativePath) == ["new.js"])
        #expect(plan.updateActions.map(\.relativePath) == ["index.html"])
        #expect(plan.deleteActions.map(\.relativePath) == ["old.css"])
        #expect(!plan.isStale(at: baseTime.addingTimeInterval(30)))
        #expect(plan.isStale(at: baseTime.addingTimeInterval(61)))
    }

    @Test("DirectoryScanner safely breaks circular local symlinks without infinite recursion (LOG-005)")
    func directoryScannerBreaksCircularSymlink() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SparkleSyncLoop-\(UUID())")
        let subA = root.appendingPathComponent("a", isDirectory: true)
        try FileManager.default.createDirectory(at: subA, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try Data("hello".utf8).write(to: subA.appendingPathComponent("hello.txt"))
        let loopLink = subA.appendingPathComponent("loop_to_root")
        try FileManager.default.createSymbolicLink(at: loopLink, withDestinationURL: root)

        let scanned = try await DirectoryScanner.scanLocal(rootURL: root, includeSHA256: true)
        #expect(scanned.contains { $0.relativePath == "a/hello.txt" && !($0.sha256 ?? "").isEmpty })
    }
}
