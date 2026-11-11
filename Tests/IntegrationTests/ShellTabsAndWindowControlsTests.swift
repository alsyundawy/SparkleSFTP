import AppKit
import Crypto
import Foundation
import NIOSSH
import SparkleCore
@testable import SparkleDesignSystem
@testable import SparkleFeatures
@testable import SparkleNetworking
@testable import SparklePersistence
@testable import SparkleSecurity
@testable import SparkleTerminal
import SwiftUI
import Testing

private actor RegTestCredStore: CredentialStoreProtocol {
    private var storage: [String: Data] = [:]

    func saveSecret(_ data: Data, for ref: SecretReference, requireTouchID _: Bool) async throws {
        storage[ref.accountKey] = data
    }

    func loadSecret(for ref: SecretReference, prompt _: String?) async throws -> Data {
        guard let data = storage[ref.accountKey] else {
            throw AppError.credentialNotFound(service: ref.accountKey)
        }
        return data
    }

    func deleteSecret(for ref: SecretReference) async throws {
        storage.removeValue(forKey: ref.accountKey)
    }

    func hasSecret(for ref: SecretReference) async -> Bool {
        storage[ref.accountKey] != nil
    }
}

private actor RegTestTrustBacking: HostTrustBackingStore {
    private var blob: Data?

    func loadTrustBlob() async throws -> Data? {
        blob
    }

    func saveTrustBlob(_ data: Data) async throws {
        blob = data
    }
}

@Suite("Shell-per-Tab, Window Controls, Preferences & Shortcut Regression Tests")
struct ShellTabsAndWindowControlsTests {
    @Test("Settings-style fixed window receives Close, Minimize & Zoom controls from SparkleWindowConfigurator")
    @MainActor
    func settingsWindowEnforcesTrafficLightButtons() async throws {
        _ = NSApplication.shared
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("SparklePrefsWin-\(UUID())")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let state = makeState(root: tmp)
        let prefsWindow = NSWindow(
            contentRect: NSRect(x: 80, y: 80, width: 640, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        prefsWindow.isReleasedWhenClosed = false
        prefsWindow.maxSize = NSSize(width: 720, height: 560)
        let hosting = NSHostingController(rootView: PreferencesView(appState: state))
        prefsWindow.contentViewController = hosting
        prefsWindow.makeKeyAndOrderFront(nil)
        defer {
            prefsWindow.orderOut(nil)
            prefsWindow.contentViewController = nil
            prefsWindow.close()
        }

        // Simulate SwiftUI Settings async pass that strips miniaturizable/zoom right after mount
        prefsWindow.layoutIfNeeded()
        hosting.view.layoutSubtreeIfNeeded()
        try? await Task.sleep(for: .milliseconds(60))

        #expect(prefsWindow.styleMask.contains(.miniaturizable))
        #expect(prefsWindow.styleMask.contains(.resizable))
        #expect(prefsWindow.maxSize.width > 10000)
        for kind: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            let btn = try #require(prefsWindow.standardWindowButton(kind))
            #expect(!btn.isHidden)
            #expect(btn.isEnabled)
        }
    }

    @Test("InteractiveFileTableView handles F7, Shift+Cmd+C, Option+Cmd+C, Cmd+Return and ignores TextView focus")
    @MainActor
    func extendedCommanderShortcutsAndTextFieldGuard() {
        _ = NSApplication.shared
        let table = InteractiveFileTableView()
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name")))
        let scroll = NSScrollView()
        scroll.documentView = table

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 320),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = scroll
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(table)
        defer {
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }

        var actions: [FilePaneContextAction] = []
        table.onContextActionShortcut = { actions.append($0) }

        fireKey(table, win: window, code: 98, mods: [.function], chars: "")
        fireKey(table, win: window, code: 8, mods: [.command, .shift], chars: "C")
        fireKey(table, win: window, code: 8, mods: [.command, .option], chars: "c")
        fireKey(table, win: window, code: 36, mods: [.command], chars: "\r")
        fireKey(table, win: window, code: 36, mods: [.option], chars: "\r")
        #expect(actions == [.newFolder, .copyFileNames, .copyFullPaths, .insertCommandLine, .inspect])

        // When a text editor is first responder, table must NOT intercept keys
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 24))
        table.addSubview(editor)
        window.makeFirstResponder(editor)
        actions.removeAll()
        if let evt = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "c",
            charactersIgnoringModifiers: "c",
            isARepeat: false,
            keyCode: 8
        ) {
            #expect(!table.performKeyEquivalent(with: evt))
        }
        let actionsCount = actions.count
        #expect(actionsCount == 0)
    }

    @Test("1-tab = 1-shell binding, switcher restore, Quick Connect availability & v0.1 Shell icon")
    @MainActor
    func oneTabOneShellBindingAndQuickConnectVisibility() async throws {
        _ = NSApplication.shared
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("SparkleShellTab-\(UUID())")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let (server, profile) = try await startLoopbackServerAndProfile(root: tmp)
        let state = makeState(root: tmp)
        state.selectLocale(code: "en")
        await state.saveProfile(profile, secretString: "pw", passphraseString: nil)
        #expect(SparkleTheme.Symbols.terminal == "terminal.fill")
        #expect(state.strings.t("nav.terminal") == "SSH Shell")
        #expect(state.isQuickConnectAvailable)

        let session1 = try await connectProfileWithAutoTrust(state: state, profile: profile)
        let tab1 = try #require(state.currentTab)
        #expect(!state.isQuickConnectAvailable && !state.isTerminalVisible)

        await state.openTerminalTab()
        await state.openTerminalTab()
        #expect(state.terminalManager.sessions.count == 1)
        let selected1 = state.terminalManager.sessions.first { $0.id == state.terminalManager.selectedSessionID }
        let shell1 = try #require(selected1)
        #expect(shell1.workspaceTabID == tab1.id && shell1.remoteSessionID == session1.id)

        let tab2 = state.openNewWorkspaceTab()
        #expect(state.isQuickConnectAvailable && !state.isTerminalVisible)
        #expect(state.terminalManager.selectedSessionID == nil)

        let session2 = try await connectProfileWithAutoTrust(state: state, profile: profile)
        await state.openTerminalTab()
        #expect(state.terminalManager.sessions.count == 2)
        let selected2 = state.terminalManager.sessions.first { $0.id == state.terminalManager.selectedSessionID }
        let shell2 = try #require(selected2)
        #expect(shell2.workspaceTabID == tab2.id && shell2.remoteSessionID == session2.id)

        _ = state.selectWorkspaceTabSync(id: tab1.id)
        #expect(state.terminalManager.selectedSessionID == shell1.id && state.isTerminalVisible)

        let closeTab2 = state.closeWorkspaceTabSync(id: tab2.id)
        if let sid2 = closeTab2.removedSessionID {
            await state.disconnect(sessionID: sid2)
        }
        #expect(state.terminalManager.sessions.count == 1)

        await state.disconnect(sessionID: session1.id)
        #expect(state.terminalManager.sessions.isEmpty && state.isQuickConnectAvailable)
        state.prepareFastShutdown()
        await state.shutdownAsyncResources()
        await server.stop()
    }

    @MainActor
    private func connectProfileWithAutoTrust(
        state: AppState,
        profile: ConnectionProfile
    ) async throws -> ActiveSessionModel {
        let trustTask = Task {
            for _ in 0 ..< 40 {
                if state.pendingHostChallenge != nil {
                    state.resolveHostChallenge(trusted: true)
                    break
                }
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
        await state.connect(profile: profile, openInNewTab: false)
        await trustTask.value
        return try #require(state.currentSession)
    }

    private func startLoopbackServerAndProfile(root: URL) async throws -> (LoopbackSSHServer, ConnectionProfile) {
        let vfs = try LoopbackSFTPVirtualFS(rootURL: root)
        let server = try await LoopbackSSHServer.start(
            hostKey: NIOSSHPrivateKey(ed25519Key: Curve25519.Signing.PrivateKey()),
            username: "ops",
            password: "pw",
            authorizedPublicKeyFingerprint: nil,
            virtualFS: vfs
        )
        let passRef = SecretReference(kind: .password)
        let profile = ConnectionProfile(
            name: "TabHost",
            protocolType: .sftp,
            host: "127.0.0.1",
            port: server.port,
            username: "ops",
            authMethod: .password,
            passwordRef: passRef,
            defaultRemotePath: "/"
        )
        return (server, profile)
    }

    @MainActor
    private func fireKey(
        _ table: InteractiveFileTableView,
        win: NSWindow,
        code: UInt16,
        mods: NSEvent.ModifierFlags,
        chars: String
    ) {
        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: mods,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: win.windowNumber,
            context: nil,
            characters: chars,
            charactersIgnoringModifiers: chars,
            isARepeat: false,
            keyCode: code
        ) else { return }
        if mods.contains(.command) {
            _ = table.performKeyEquivalent(with: event)
        } else {
            table.keyDown(with: event)
        }
    }

    @MainActor
    private func makeState(root: URL) -> AppState {
        let state = AppState(
            credentialStore: RegTestCredStore(),
            hostTrustStore: HostTrustStore(backingStore: RegTestTrustBacking()),
            connectionStore: ConnectionStore(fileURL: root.appendingPathComponent("conn.json")),
            transferJournal: nil,
            snippetStore: CommandSnippetStore(fileURL: root.appendingPathComponent("snip.json"))
        )
        state.didBootstrap = true
        return state
    }
}
