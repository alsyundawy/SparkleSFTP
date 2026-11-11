import Foundation
import SparkleCore
@testable import SparkleSynchronization
import Testing

@Suite("Bidirectional & Reverse Synchronization Planner Tests")
struct BidirectionalSyncTests {
    @Test("SyncPlanner bidirectional mode selects newest side without deleting extras")
    func bidirectionalNewestWinsWithoutDeletingExtras() {
        let now = Date()
        let older = now.addingTimeInterval(-300)
        let newer = now.addingTimeInterval(300)

        let local: [ScannedFileEntry] = [
            ScannedFileEntry(relativePath: "local-only.txt", size: 10, modificationTime: now, isDirectory: false),
            ScannedFileEntry(relativePath: "shared.txt", size: 120, modificationTime: newer, isDirectory: false),
            ScannedFileEntry(relativePath: "older-local.txt", size: 90, modificationTime: older, isDirectory: false)
        ]
        let remote: [ScannedFileEntry] = [
            ScannedFileEntry(relativePath: "remote-only.txt", size: 20, modificationTime: now, isDirectory: false),
            ScannedFileEntry(relativePath: "shared.txt", size: 100, modificationTime: older, isDirectory: false),
            ScannedFileEntry(relativePath: "older-local.txt", size: 95, modificationTime: newer, isDirectory: false)
        ]

        let plan = SyncPlanner.buildPlan(
            source: local,
            destination: remote,
            direction: .bidirectional,
            mode: .sizeAndMtime,
            deleteExtras: true,
            now: now
        )
        #expect(plan.direction == .bidirectional)
        #expect(!plan.deleteExtras)
        #expect(plan.deleteActions.isEmpty)

        let uploadLocalOnly = plan.actions.first { $0.relativePath == "local-only.txt" }
        #expect(uploadLocalOnly?.transferDirection == .upload)
        #expect(uploadLocalOnly?.kind == .create)

        let downloadRemoteOnly = plan.actions.first { $0.relativePath == "remote-only.txt" }
        #expect(downloadRemoteOnly?.transferDirection == .download)
        #expect(downloadRemoteOnly?.kind == .create)

        let updateShared = plan.actions.first { $0.relativePath == "shared.txt" }
        #expect(updateShared?.transferDirection == .upload)
        #expect(updateShared?.kind == .update)

        let updateOlderLocal = plan.actions.first { $0.relativePath == "older-local.txt" }
        #expect(updateOlderLocal?.transferDirection == .download)
        #expect(updateOlderLocal?.kind == .update)
    }

    @Test("SyncPlanner remoteToLocal mirrors remote additions and deletes stale local extras when enabled")
    func remoteToLocalMirrorPlan() {
        let now = Date()
        let local = [ScannedFileEntry(relativePath: "stale.tmp", size: 5, modificationTime: now, isDirectory: false)]
        let remote = [ScannedFileEntry(relativePath: "deploy.env", size: 32, modificationTime: now, isDirectory: false)]

        let plan = SyncPlanner.buildPlan(
            source: local,
            destination: remote,
            direction: .remoteToLocal,
            mode: .sizeOnly,
            deleteExtras: true,
            now: now
        )
        #expect(plan.createActions.first?.transferDirection == .download)
        #expect(plan.deleteActions.first?.transferDirection == .download)
        #expect(plan.deleteActions.first?.relativePath == "stale.tmp")
    }
}
