import AppKit
import Foundation
import SparkleCore
import SparkleDesignSystem
@testable import SparkleFeatures
import SparklePersistence
import SparkleSecurity
@testable import SparkleTerminal
import SwiftUI
import Testing

@Suite("Standalone iTerm2 Terminal, Error Suppression & Batch Journal Tests")
struct TransferAndTerminalRegressionTests {
    @Test("TerminalSplitNode supports vertical/horizontal split, cycling, and collapse on removal")
    func terminalSplitNodeTreeOperations() {
        let firstID = UUID()
        let secondID = UUID()
        let thirdID = UUID()
        let initial = TerminalSplitNode.pane(firstID)
        let sideBySide = initial.splitting(targetPaneID: firstID, axis: .verticalDivider, newPaneID: secondID)
        let nested = sideBySide.splitting(targetPaneID: secondID, axis: .horizontalDivider, newPaneID: thirdID)

        #expect(nested.paneIDs == [firstID, secondID, thirdID])
        #expect(nested.adjacentPaneID(from: firstID, delta: 1) == secondID)
        #expect(nested.adjacentPaneID(from: thirdID, delta: 1) == firstID)
        #expect(nested.adjacentPaneID(from: firstID, delta: -1) == thirdID)

        let afterRemovingSecond = nested.removing(targetPaneID: secondID)
        #expect(afterRemovingSecond?.paneIDs == [firstID, thirdID])
        let afterRemovingAll = afterRemovingSecond?
            .removing(targetPaneID: firstID)?
            .removing(targetPaneID: thirdID)
        #expect(afterRemovingAll == nil)
    }

    @MainActor
    @Test("StandaloneTerminalManager manages tabs, splits, SSH validation, font zoom, and cleanup")
    func standaloneTerminalManagerLifecycle() throws {
        let manager = StandaloneTerminalManager()
        manager.ensureInitialTab(workingDirectory: FileManager.default.homeDirectoryForCurrentUser)
        #expect(manager.tabs.count == 1)

        let firstPaneID = try #require(manager.focusedPane?.id)
        let execPath = try #require(manager.focusedPane?.launchConfig.executable)
        #expect(FileManager.default.isExecutableFile(atPath: execPath))

        let splitPane = try #require(manager.splitFocusedPane(axis: .verticalDivider))
        #expect(manager.activeTab?.rootNode.paneIDs == [firstPaneID, splitPane.id])
        #expect(manager.focusedPane?.id == splitPane.id)

        manager.focusAdjacentPane(delta: 1)
        #expect(manager.focusedPane?.id == firstPaneID)

        let safeProfile = ConnectionProfile(
            name: "Prod",
            protocolType: .sftp,
            host: "ssh.example.com",
            port: 2222,
            username: "deploy"
        )
        let sshTab = try manager.openSSHTab(for: safeProfile)
        #expect(manager.tabs.count == 2)
        let sshPane = try #require(manager.panes[sshTab.focusedPaneID])
        #expect(sshPane.launchConfig.kind == .ssh)
        let expectedSSHArgs = ["-p", "2222", "-o", "ServerAliveInterval=30", "--", "deploy@ssh.example.com"]
        #expect(sshPane.launchConfig.args == expectedSSHArgs)

        let unsafeProfile = ConnectionProfile(
            name: "Bad",
            protocolType: .sftp,
            host: "-oProxyCommand=evil",
            port: 22,
            username: "alice"
        )
        #expect(throws: AppError.self) {
            _ = try manager.openSSHTab(for: unsafeProfile)
        }

        manager.increaseFontSize()
        #expect(manager.fontSize == 14.0)
        manager.resetFontSize()
        #expect(manager.fontSize == 13.0)

        manager.closePane(id: splitPane.id)
        manager.terminateAll()
        #expect(manager.tabs.isEmpty)
        #expect(manager.panes.isEmpty)
    }

    @Test("TransferJournal upsertBatch and deleteBatch persist atomically")
    func transferJournalBatchOperations() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SparkleJournalBatch-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let journal = try TransferJournal(databaseURL: dir.appendingPathComponent("journal.sqlite3"))
        let meta1 = TransferTaskMetadata(
            direction: .upload,
            source: .local(url: dir.appendingPathComponent("1.bin")),
            destination: .remote(profileID: UUID(), host: "srv", path: "/1.bin"),
            totalBytes: 128
        )
        let meta2 = TransferTaskMetadata(
            direction: .download,
            source: .remote(profileID: UUID(), host: "srv", path: "/2.bin"),
            destination: .local(url: dir.appendingPathComponent("2.bin")),
            totalBytes: 256
        )
        try await journal.upsertBatch([
            TransferJournalRecord(id: meta1.id, metadata: meta1, statusCode: "completed"),
            TransferJournalRecord(id: meta2.id, metadata: meta2, statusCode: "failed", errorDescription: "Timeout")
        ])
        let loaded = try await journal.fetchAll()
        #expect(loaded.count == 2)

        try await journal.deleteBatch(ids: [meta1.id])
        let remaining = try await journal.fetchAll()
        #expect(remaining.map(\.id) == [meta2.id])
    }

    @MainActor
    @Test("AppState suppresses CancellationError popups and persists upload/download conflict policies")
    func appStateCancellationSuppressionAndConflictPolicyPersistence() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("SparkleAppReg-\(UUID())")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let savedLegacy = UserDefaults.standard.string(forKey: "sparklesftp.conflictPolicy")
        let savedUpload = UserDefaults.standard.string(forKey: "sparklesftp.uploadConflictPolicy")
        let savedDownload = UserDefaults.standard.string(forKey: "sparklesftp.downloadConflictPolicy")
        defer {
            restoreDefault("sparklesftp.conflictPolicy", value: savedLegacy)
            restoreDefault("sparklesftp.uploadConflictPolicy", value: savedUpload)
            restoreDefault("sparklesftp.downloadConflictPolicy", value: savedDownload)
        }

        let state = makeIsolatedAppState(tempDir: tempDir)
        state.reportNonCancellationError(CancellationError())
        #expect(state.lastError == nil)

        state.reportNonCancellationError(URLError(.cancelled))
        #expect(state.lastError == nil)

        state.reportNonCancellationError(AppError.permissionDenied(path: "/x"), asBannerOnly: true)
        #expect(state.lastError == nil)
        #expect(state.statusBannerMessage?.contains("/x") == true)

        state.defaultUploadConflictPolicy = .overwriteIfDifferentSize
        state.defaultDownloadConflictPolicy = .rename
        await state.applyConflictPolicySettings()

        let reloaded = makeIsolatedAppState(tempDir: tempDir)
        #expect(reloaded.defaultUploadConflictPolicy == .overwriteIfDifferentSize)
        #expect(reloaded.defaultDownloadConflictPolicy == .rename)
    }

    @MainActor
    @Test("Context menu open guards defer table reload until menu closes")
    func contextMenuDeferReloadGuards() {
        var paneSel: Set<String> = []
        let paneTable = FilePaneTableView(
            files: [],
            selectedIDs: Binding(get: { paneSel }, set: { paneSel = $0 }),
            onActivateRow: { _ in },
            onSortColumn: { _ in },
            onFocusPane: {}
        )
        let paneCoordinator = paneTable.makeCoordinator()
        #expect(!paneCoordinator.isMenuOpen)
        paneCoordinator.menuWillOpen(NSMenu())
        #expect(paneCoordinator.isMenuOpen)
        paneCoordinator.menuDidClose(NSMenu())
        #expect(!paneCoordinator.isMenuOpen)

        var connSel: Set<UUID> = []
        let connTable = ConnectionListTableView(
            rows: [],
            selectedIDs: Binding(get: { connSel }, set: { connSel = $0 }),
            strings: AppStrings(),
            palette: SparkleThemeCatalog.defaultLight,
            onConnect: { _ in },
            onConnectInNewTab: { _ in },
            onConnectInNewWindow: { _ in },
            onOpenExternalTerminal: { _ in },
            onNewConnection: {},
            onNewGroup: {},
            onSelectAll: {},
            onEdit: { _ in },
            onClone: { _ in },
            onRequestDelete: { _ in },
            onDeleteGroup: { _ in }
        )
        let connCoordinator = connTable.makeCoordinator()
        #expect(!connCoordinator.isMenuOpen)
        connCoordinator.menuWillOpen(NSMenu())
        #expect(connCoordinator.isMenuOpen)
        connCoordinator.menuDidClose(NSMenu())
        #expect(!connCoordinator.isMenuOpen)
    }

    @MainActor
    private func makeIsolatedAppState(tempDir: URL) -> AppState {
        AppState(
            credentialStore: KeychainService(serviceIdentifier: "com.sparklesftp.test.\(UUID().uuidString)"),
            hostTrustStore: HostTrustStore(backingStore: FileHostTrustBackingStore(
                fileURL: tempDir.appendingPathComponent("hosts.json"),
                legacyKeychainStore: nil
            )),
            connectionStore: ConnectionStore(fileURL: tempDir.appendingPathComponent("conns.json")),
            transferJournal: nil,
            snippetStore: CommandSnippetStore(fileURL: tempDir.appendingPathComponent("snippets.json"))
        )
    }

    private func restoreDefault(_ key: String, value: String?) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
