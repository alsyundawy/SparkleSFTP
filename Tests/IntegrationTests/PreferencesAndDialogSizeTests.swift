import AppKit
import Foundation
import SparkleCore
@testable import SparkleDesignSystem
@testable import SparkleFeatures
@testable import SparkleNetworking
@testable import SparklePersistence
@testable import SparkleSecurity
@testable import SparkleSynchronization
@testable import SparkleTerminal
@testable import SparkleTransferEngine
import SwiftUI
import Testing

private actor DialogTestCredStore: CredentialStoreProtocol {
    func saveSecret(_: Data, for _: SecretReference, requireTouchID _: Bool) async throws {}

    func loadSecret(for ref: SecretReference, prompt _: String?) async throws -> Data {
        throw AppError.credentialNotFound(service: ref.accountKey)
    }

    func deleteSecret(for _: SecretReference) async throws {}

    func hasSecret(for _: SecretReference) async -> Bool {
        false
    }
}

private actor DialogTestTrustBacking: HostTrustBackingStore {
    func loadTrustBlob() async throws -> Data? {
        nil
    }

    func saveTrustBlob(_: Data) async throws {}
}

@Suite("Preferences Window Controls & Fixed Dialog Box Size Tests")
struct PreferencesAndDialogSizeTests {
    @Test("Preferences window provides Close/Minimize/Zoom, single instance, live locale sync & constant tab size")
    @MainActor
    func preferencesWindowTrafficLightsAndFixedTabGeometry() async throws {
        _ = NSApplication.shared
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("SparklePrefsCtrl-\(UUID())")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let state = makeState(root: tmp)
        state.openPreferencesWindow()
        try? await Task.sleep(for: .milliseconds(60))

        let prefsID = NSUserInterfaceItemIdentifier("sparkle.preferences")
        let prefsWindow = try #require(NSApp.windows.first { $0.identifier == prefsID && $0.isVisible })
        defer {
            prefsWindow.orderOut(nil)
            prefsWindow.contentViewController = nil
            prefsWindow.close()
        }

        assertTrafficLightsActive(in: prefsWindow)
        let initialContentSize = prefsWindow.contentLayoutRect.size
        #expect(abs(initialContentSize.width - 760) <= 1)
        #expect(abs(initialContentSize.height - 600) <= 1)

        if let tabView = firstTabView(in: prefsWindow.contentView), tabView.numberOfTabViewItems > 1 {
            for index in 0 ..< tabView.numberOfTabViewItems {
                tabView.selectTabViewItem(at: index)
                prefsWindow.layoutIfNeeded()
                try? await Task.sleep(for: .milliseconds(25))
                let currentSize = prefsWindow.contentLayoutRect.size
                #expect(abs(currentSize.width - initialContentSize.width) <= 1)
                #expect(abs(currentSize.height - initialContentSize.height) <= 1)
            }
        }

        let secondState = makeState(root: tmp)
        secondState.openPreferencesWindow()
        try? await Task.sleep(for: .milliseconds(30))
        let visibleCount = NSApp.windows.count { $0.identifier == prefsID && $0.isVisible }
        #expect(visibleCount == 1)

        state.selectLocale(code: "id")
        try? await Task.sleep(for: .milliseconds(25))
        #expect(prefsWindow.title == state.strings.t("nav.settings"))
        state.selectLocale(code: "en")
        #expect(prefsWindow.title == state.strings.t("nav.settings"))
    }

    @Test("About window keeps fixed 720x560 size across updates with active Close/Minimize/Zoom")
    @MainActor
    func aboutWindowFixedGeometryAndTrafficLights() async throws {
        _ = NSApplication.shared
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("SparkleAboutSize-\(UUID())")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let state = makeState(root: tmp)
        state.openAboutWindow()
        try? await Task.sleep(for: .milliseconds(60))

        let aboutID = NSUserInterfaceItemIdentifier("sparkle.about")
        let aboutWindow = try #require(NSApp.windows.first { $0.identifier == aboutID && $0.isVisible })
        defer {
            aboutWindow.orderOut(nil)
            aboutWindow.contentViewController = nil
            aboutWindow.close()
        }

        assertTrafficLightsActive(in: aboutWindow)
        #expect(abs(aboutWindow.contentLayoutRect.size.width - 720) <= 1)
        #expect(abs(aboutWindow.contentLayoutRect.size.height - 560) <= 1)

        state.selectLocale(code: "id")
        #expect(aboutWindow.title == state.strings.t("nav.about"))
        state.selectLocale(code: "en")
    }

    @Test("Modal dialog views lock exact fixed box dimensions even as content changes")
    @MainActor
    func modalDialogSheetsLockExactFixedSizes() throws {
        _ = NSApplication.shared
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("SparkleDialogFixed-\(UUID())")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let state = makeState(root: tmp)
        let sampleFile = RemoteFile(
            name: "index.html",
            path: RemotePath("/var/www/index.html"),
            size: 512,
            isDirectory: false,
            permissions: 0o644
        )
        verifyTransferAndSyncDialogSizes(state: state, sampleFile: sampleFile)
        verifyConnectionAndCommanderDialogSizes(state: state, sampleFile: sampleFile)
    }

    @MainActor
    private func verifyTransferAndSyncDialogSizes(state: AppState, sampleFile: RemoteFile) {
        let syncHost = NSHostingController(rootView: SyncPreviewSheet(appState: state))
        assertFixedFittingSize(syncHost, width: 680, height: 500)
        state.syncPlan = SyncPlan(actions: [
            SyncAction(relativePath: "deploy/app.bin", kind: .create, isDirectory: false, size: 1024),
            SyncAction(relativePath: "old.log", kind: .delete, isDirectory: false, size: 128)
        ])
        syncHost.view.layoutSubtreeIfNeeded()
        assertFixedFittingSize(syncHost, width: 680, height: 500)

        let conflict = ConflictContext(
            taskID: UUID(),
            sourceDisplayPath: "/Users/demo/archive.tar.gz",
            destinationDisplayPath: "/var/www/archive.tar.gz",
            existingSize: 2048,
            incomingSize: 4096
        )
        assertFixedFittingSize(
            NSHostingController(rootView: ConflictResolutionSheet(appState: state, conflict: conflict)),
            width: 580,
            height: 560
        )
        assertFixedFittingSize(
            NSHostingController(
                rootView: CopyMoveItemSheet(
                    request: CopyMoveRequest(
                        files: [sampleFile],
                        isLocal: true,
                        isMove: false,
                        defaultDestinationDir: "/tmp"
                    ),
                    hasActiveSession: true,
                    oppositeDefaultPath: "/var/www",
                    sameSideDefaultPath: "/tmp"
                ) { _, _ in }
            ),
            width: 480,
            height: 230
        )
    }

    @MainActor
    private func verifyConnectionAndCommanderDialogSizes(state: AppState, sampleFile: RemoteFile) {
        let challenge = HostKeyChallenge(
            host: "prod.example.com",
            port: 22,
            algorithm: "ssh-ed25519",
            fingerprintSHA256: "SHA256:fixedBoxRegressionFingerprintExampleValue01"
        )
        assertFixedFittingSize(
            NSHostingController(rootView: HostKeyVerificationSheet(appState: state, challenge: challenge)),
            width: 500,
            height: 240
        )
        let promptReq = CredentialPromptRequest(
            host: "prod.example.com",
            port: 22,
            username: "deploy",
            authMethod: .password,
            promptTitle: "Password"
        )
        assertFixedFittingSize(
            NSHostingController(rootView: CredentialPromptSheet(appState: state, request: promptReq)),
            width: 460,
            height: 220
        )
        assertFixedFittingSize(
            NSHostingController(rootView: PermissionsEditorSheet(file: sampleFile) { _ in }),
            width: 360,
            height: 190
        )
        assertFixedFittingSize(
            NSHostingController(rootView: RenameItemSheet(item: sampleFile) { _ in }),
            width: 380,
            height: 165
        )
        assertFixedFittingSize(
            NSHostingController(rootView: ImportConnectionsSheet(appState: state)),
            width: 680,
            height: 520
        )
        assertFixedFittingSize(
            NSHostingController(rootView: SecurityDiagnosticsView(appState: state)),
            width: 600,
            height: 420
        )
        assertFixedFittingSize(
            NSHostingController(rootView: ConnectionEditorView(appState: state, existingProfile: nil)),
            width: 520,
            height: 640
        )
    }

    @Test("MainWindowView keeps Close/Minimize/Zoom and toolbar above NSHostingView in NSThemeFrame")
    @MainActor
    func mainWindowTitlebarNotObscuredByContent() async throws {
        _ = NSApplication.shared
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("SparkleMWZOrder-\(UUID())")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let state = makeState(root: tmp)
        state.selectTheme(SparkleThemeCatalog.palette(id: "tomorrowNight", appearanceMode: .dark, systemIsDark: true))
        let hosting = NSHostingController(rootView: MainWindowView(appState: state))
        let window = NSWindow(
            contentRect: NSRect(x: 80, y: 80, width: 1080, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = hosting
        window.makeKeyAndOrderFront(nil)
        defer {
            window.orderOut(nil)
            window.contentViewController = nil
            window.close()
        }

        for _ in 0 ..< 4 {
            window.layoutIfNeeded()
            hosting.view.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(35))
        }

        assertTrafficLightsActive(in: window)
        let contentView = try #require(window.contentView)
        let themeFrame = try #require(contentView.superview)
        let closeBtn = try #require(window.standardWindowButton(.closeButton))
        let titlebarContainer = try #require(closeBtn.superview?.superview)
        #expect(titlebarContainer.superview === themeFrame)
        let contentIndex = try #require(themeFrame.subviews.firstIndex(of: contentView))
        let titlebarIndex = try #require(themeFrame.subviews.firstIndex(of: titlebarContainer))
        #expect(titlebarIndex > contentIndex)
        #expect(!titlebarContainer.isHidden && titlebarContainer.alphaValue > 0.99)
    }
}

@MainActor
private extension PreferencesAndDialogSizeTests {
    func assertTrafficLightsActive(in window: NSWindow) {
        let requiredMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
        #expect(window.styleMask.isSuperset(of: requiredMask))
        #expect(window.collectionBehavior.contains(.fullScreenPrimary))
        #expect(window.maxSize.width > 10000 && window.maxSize.height > 10000)
        for kind: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            let btn = window.standardWindowButton(kind)
            #expect(btn != nil)
            #expect(btn?.isHidden == false)
            #expect(btn?.isEnabled == true)
        }
    }

    func assertFixedFittingSize(
        _ controller: NSViewController,
        width: CGFloat,
        height: CGFloat
    ) {
        controller.view.layoutSubtreeIfNeeded()
        let size = controller.view.fittingSize
        #expect(abs(size.width - width) <= 2)
        #expect(abs(size.height - height) <= 2)
    }

    func firstTabView(in view: NSView?) -> NSTabView? {
        guard let view else { return nil }
        if let tabView = view as? NSTabView {
            return tabView
        }
        for subview in view.subviews {
            if let found = firstTabView(in: subview) {
                return found
            }
        }
        return nil
    }

    func makeState(root: URL) -> AppState {
        let state = AppState(
            credentialStore: DialogTestCredStore(),
            hostTrustStore: HostTrustStore(backingStore: DialogTestTrustBacking()),
            connectionStore: ConnectionStore(fileURL: root.appendingPathComponent("conn.json")),
            transferJournal: nil,
            snippetStore: CommandSnippetStore(fileURL: root.appendingPathComponent("snip.json"))
        )
        state.didBootstrap = true
        return state
    }
}
