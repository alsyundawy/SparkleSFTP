import AppKit
import Crypto
import Foundation
import NIOSSH
import SparkleCore
@testable import SparkleDesignSystem
@testable import SparkleFeatures
@testable import SparklePersistence
@testable import SparkleSecurity
@testable import SparkleTerminal
import SwiftUI
import Testing

private actor WinUITestCredStore: CredentialStoreProtocol {
    func saveSecret(_: Data, for _: SecretReference, requireTouchID _: Bool) async throws {}

    func loadSecret(for ref: SecretReference, prompt _: String?) async throws -> Data {
        throw AppError.credentialNotFound(service: ref.accountKey)
    }

    func deleteSecret(for _: SecretReference) async throws {}

    func hasSecret(for _: SecretReference) async -> Bool {
        false
    }
}

private actor WinUITestTrustBacking: HostTrustBackingStore {
    func loadTrustBlob() async throws -> Data? {
        nil
    }

    func saveTrustBlob(_: Data) async throws {}
}

@Suite("Window Controls, Quickconnect & Shortcuts Regression Tests")
struct WindowControlsAndShortcutsTests {
    @Test("AboutWindowController enables Close/Minimize/Zoom and syncs active theme chrome")
    @MainActor
    func aboutWindowTrafficLightsAndThemeSync() async throws {
        _ = NSApplication.shared
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("SparkleWinBtn-\(UUID())")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let state = makeState(root: tmp)
        let controller = AboutWindowController()
        controller.present(appState: state)
        try? await Task.sleep(for: .milliseconds(50))

        let aboutWindow = try #require(
            NSApp.windows.first { $0.title == state.strings.t("nav.about") && $0.isVisible }
        )
        defer {
            aboutWindow.orderOut(nil)
            aboutWindow.contentViewController = nil
            aboutWindow.close()
        }

        let requiredMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
        #expect(aboutWindow.styleMask.isSuperset(of: requiredMask))
        for kind: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            let btn = try #require(aboutWindow.standardWindowButton(kind))
            #expect(!btn.isHidden)
            #expect(btn.isEnabled)
        }

        let dracula = SparkleThemeCatalog.palette(id: "dracula", appearanceMode: .dark, systemIsDark: true)
        state.selectTheme(dracula)
        controller.present(appState: state)
        #expect(aboutWindow.appearance?.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
    }

    @Test("v0.1 shell icon uses terminal.fill and Local Shell UI/shortcuts are removed")
    @MainActor
    func shellIconAndNoLocalShell() {
        #expect(SparkleTheme.Symbols.terminal == "terminal.fill")
        let manager = TerminalSessionManager()
        #expect(manager.sessions.isEmpty)
        let enStrings = LocalizationCatalog.loadBundledStrings(code: "en")
        let idStrings = LocalizationCatalog.loadBundledStrings(code: "id")
        #expect(enStrings["nav.localShell"] == nil)
        #expect(idStrings["nav.localShell"] == nil)
    }

    @Test("Quickconnect hides when session connected and reappears on new unconnected tab")
    func quickConnectVisibilityFollowsSessionConnection() async throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("SparkleQCVis-\(UUID())")
        let remoteDir = tmp.appendingPathComponent("remote", isDirectory: true)
        try FileManager.default.createDirectory(at: remoteDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let vfs = try LoopbackSFTPVirtualFS(rootURL: remoteDir)
        let server = try await LoopbackSSHServer.start(
            hostKey: NIOSSHPrivateKey(ed25519Key: Curve25519.Signing.PrivateKey()),
            username: "deploy",
            password: "pw",
            authorizedPublicKeyFingerprint: nil,
            virtualFS: vfs
        )
        try await runQuickConnectWindowCheck(root: tmp, port: server.port)
        await server.stop()
    }

    @MainActor
    private func runQuickConnectWindowCheck(root: URL, port: Int) async throws {
        _ = NSApplication.shared
        let state = makeState(root: root)
        await state.refreshLocalDirectory(root, recordHistory: false)
        try await verifyQuickConnectTransitions(state: state, port: port)
        state.prepareFastShutdown()
        await state.shutdownAsyncResources()
    }

    @Test("InteractiveFileTableView handles shortcuts and Tab pane switch cleanly")
    @MainActor
    func fileTableShortcutsAndValidation() {
        _ = NSApplication.shared
        let table = InteractiveFileTableView()
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name")))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = table
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(table)
        defer {
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }

        assertTableShortcutCallbacks(on: table, window: window)
    }

    @MainActor
    private func assertTableShortcutCallbacks(on table: InteractiveFileTableView, window: NSWindow) {
        var actions: [FilePaneContextAction] = []
        var didSwitchPane = false
        var didGoParent = false
        table.onContextActionShortcut = { actions.append($0) }
        table.onSwitchPane = { didSwitchPane = true }
        table.onGoParent = { didGoParent = true }

        sendKey(48, chars: "\t", to: table, window: window)
        sendKey(51, chars: "\u{7F}", to: table, window: window)
        sendKey(51, mods: [.command], chars: "\u{7F}", to: table, window: window)
        sendKey(120, chars: "", to: table, window: window)

        #expect(didSwitchPane)
        #expect(didGoParent)
        #expect(actions == [.delete, .rename])

        let copyItem = NSMenuItem(
            title: "Copy",
            action: #selector(InteractiveFileTableView.copy(_:)),
            keyEquivalent: "c"
        )
        #expect(!table.validateUserInterfaceItem(copyItem))
    }

    @MainActor
    private func sendKey(
        _ keyCode: UInt16,
        mods: NSEvent.ModifierFlags = [],
        chars: String,
        to table: InteractiveFileTableView,
        window: NSWindow
    ) {
        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: mods,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            characters: chars,
            charactersIgnoringModifiers: chars,
            isARepeat: false,
            keyCode: keyCode
        ) else { return }
        if mods.contains(.command) {
            _ = table.performKeyEquivalent(with: event)
        } else {
            table.keyDown(with: event)
        }
    }

    @MainActor
    private func verifyQuickConnectTransitions(state: AppState, port: Int) async throws {
        state.isQuickConnectBarVisible = true
        let hosting = NSHostingController(rootView: MainWindowView(appState: state))
        let window = NSWindow(
            contentRect: NSRect(x: 60, y: 60, width: 1080, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = hosting
        window.orderFront(nil)
        defer {
            window.orderOut(nil)
            window.contentViewController = nil
            window.close()
        }

        await pumpWindowLayout(window: window, hosting: hosting)
        for kind: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            let button = try #require(window.standardWindowButton(kind))
            #expect(!button.isHidden)
            #expect(button.isEnabled)
        }

        let hostPlaceholder = state.strings.t("conn.host")
        let toggleHelp = state.strings.t("tabs.quickConnectToggle")
        let rootView = try #require(window.contentView?.superview)
        #expect(state.currentSession == nil)
        #expect(hasQuickConnectBar(hostPlaceholder: hostPlaceholder, in: rootView))
        #expect(hasQuickConnectToggle(help: toggleHelp, in: rootView))

        await connectQuickConnect(state: state, port: port)
        await pumpWindowLayout(window: window, hosting: hosting)
        #expect(state.currentSession != nil)
        #expect(!hasQuickConnectBar(hostPlaceholder: hostPlaceholder, in: rootView))
        #expect(!hasQuickConnectToggle(help: toggleHelp, in: rootView))

        _ = state.openNewWorkspaceTab()
        await pumpWindowLayout(window: window, hosting: hosting)
        #expect(state.currentSession == nil)
        #expect(hasQuickConnectBar(hostPlaceholder: hostPlaceholder, in: rootView))
        #expect(hasQuickConnectToggle(help: toggleHelp, in: rootView))
    }

    @MainActor
    private func connectQuickConnect(state: AppState, port: Int) async {
        state.quickConnectProtocol = .sftp
        state.quickConnectHost = "127.0.0.1"
        state.quickConnectPort = String(port)
        state.quickConnectUsername = "deploy"
        state.quickConnectPassword = "pw"
        state.quickConnectSaveProfile = false
        let trustTask = Task {
            for _ in 0 ..< 40 {
                if state.pendingHostChallenge != nil {
                    state.resolveHostChallenge(trusted: true)
                    break
                }
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
        await state.performQuickConnect()
        _ = await trustTask.value
    }

    @MainActor
    private func pumpWindowLayout(window: NSWindow, hosting: NSViewController) async {
        for _ in 0 ..< 4 {
            window.layoutIfNeeded()
            hosting.view.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(25))
        }
    }

    @MainActor
    private func hasQuickConnectBar(hostPlaceholder: String, in view: NSView) -> Bool {
        if view.accessibilityIdentifier() == "quickConnectBar" {
            return true
        }
        if let field = view as? NSTextField, field.placeholderString == hostPlaceholder {
            return true
        }
        return view.subviews.contains { hasQuickConnectBar(hostPlaceholder: hostPlaceholder, in: $0) }
    }

    @MainActor
    private func hasQuickConnectToggle(help: String, in view: NSView) -> Bool {
        if let btn = view as? NSButton,
           !btn.isHidden,
           btn.isEnabled,
           btn.frame.width > 0,
           btn.accessibilityIdentifier() == "quickConnectToggleButton"
           || btn.toolTip == help
           || btn.title == help {
            return true
        }
        return view.subviews.contains { hasQuickConnectToggle(help: help, in: $0) }
    }

    @MainActor
    private func makeState(root: URL) -> AppState {
        let state = AppState(
            credentialStore: WinUITestCredStore(),
            hostTrustStore: HostTrustStore(backingStore: WinUITestTrustBacking()),
            connectionStore: ConnectionStore(fileURL: root.appendingPathComponent("conn.json")),
            transferJournal: nil,
            snippetStore: CommandSnippetStore(fileURL: root.appendingPathComponent("snip.json"))
        )
        state.didBootstrap = true
        return state
    }
}
