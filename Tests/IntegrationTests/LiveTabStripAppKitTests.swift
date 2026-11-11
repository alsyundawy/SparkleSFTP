import AppKit
import Foundation
import SparkleCore
@testable import SparkleFeatures
import SparklePersistence
import SparkleSecurity
import SparkleTerminal
import SwiftUI
import Testing

private actor EphemeralUITestCredStore: CredentialStoreProtocol {
    func saveSecret(_: Data, for _: SecretReference, requireTouchID _: Bool) async throws {}
    func loadSecret(for ref: SecretReference, prompt _: String?) async throws -> Data {
        throw AppError.credentialNotFound(service: ref.accountKey)
    }

    func deleteSecret(for _: SecretReference) async throws {}
    func hasSecret(for _: SecretReference) async -> Bool {
        false
    }
}

private actor EphemeralUITestTrustBacking: HostTrustBackingStore {
    func loadTrustBlob() async throws -> Data? {
        nil
    }

    func saveTrustBlob(_: Data) async throws {}
}

private struct MountedTestWindow {
    let window: NSWindow
    let hosting: NSViewController
    let rootView: NSView
}

@Suite("Live AppKit NSWindow Tab Strip UI Tests")
struct LiveTabStripAppKitTests {
    @Test("AppKit tab strip fits inside detail bounds and switches & closes old tabs on mouse click")
    @MainActor
    func liveWindowTabStripSwitchingAndClosing() async throws {
        _ = NSApplication.shared
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("LiveTabs-\(UUID())")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let state = makeTestState(root: tmp)
        let tab1 = state.workspaceTabs[0]
        let tab2 = state.openNewWorkspaceTab()
        let tab3 = state.openNewWorkspaceTab()
        #expect(state.workspaceTabs.count == 3)
        #expect(tab2.title != tab3.title)
        #expect(state.activeTabID == tab3.id)

        let mounted = try await mountMainWindow(state: state)
        defer {
            mounted.window.orderOut(nil)
            mounted.window.contentViewController = nil
            mounted.window.close()
        }

        try assertChipsInsideDetailBounds(tabIDs: [tab1.id, tab2.id, tab3.id], mounted: mounted)
        try await verifySwitchingBetweenTabs(tab1ID: tab1.id, tab2ID: tab2.id, state: state, mounted: mounted)
        try await verifyClosingOldAndInactiveTabs(
            tabIDs: [tab1.id, tab2.id, tab3.id],
            state: state,
            mounted: mounted
        )
        state.prepareFastShutdown()
        await state.shutdownAsyncResources()
    }

    @MainActor
    private func makeTestState(root: URL) -> AppState {
        let state = AppState(
            credentialStore: EphemeralUITestCredStore(),
            hostTrustStore: HostTrustStore(backingStore: EphemeralUITestTrustBacking()),
            connectionStore: ConnectionStore(fileURL: root.appendingPathComponent("conn.json")),
            transferJournal: nil,
            snippetStore: CommandSnippetStore(fileURL: root.appendingPathComponent("snip.json"))
        )
        state.didBootstrap = true
        return state
    }

    @MainActor
    private func mountMainWindow(state: AppState) async throws -> MountedTestWindow {
        let hosting = NSHostingController(rootView: MainWindowView(appState: state))
        let window = NSWindow(
            contentRect: NSRect(x: 60, y: 60, width: 960, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = hosting
        window.orderFront(nil)
        await pumpLayout(window: window, hosting: hosting)
        let rootView = try #require(window.contentView?.superview)
        return MountedTestWindow(window: window, hosting: hosting, rootView: rootView)
    }

    @MainActor
    private func assertChipsInsideDetailBounds(tabIDs: [UUID], mounted: MountedTestWindow) throws {
        let chips = collectViews(ofType: WorkspaceTabChipView.self, in: mounted.rootView)
        #expect(chips.count == tabIDs.count)
        let detailMinX = findDetailColumnMinX(in: mounted.rootView) ?? 0
        for tabID in tabIDs {
            let chip = try #require(chips.first { $0.tabID == tabID })
            let rectInRoot = chip.convert(chip.bounds, to: mounted.rootView)
            #expect(rectInRoot.minX >= detailMinX)
            #expect(rectInRoot.maxY <= mounted.window.contentLayoutRect.maxY + 1)
            #expect(rectInRoot.minY >= 0)
        }
    }

    @MainActor
    private func verifySwitchingBetweenTabs(
        tab1ID: UUID,
        tab2ID: UUID,
        state: AppState,
        mounted: MountedTestWindow
    ) async throws {
        let chips = collectViews(ofType: WorkspaceTabChipView.self, in: mounted.rootView)
        let chip1 = try #require(chips.first { $0.tabID == tab1ID })
        let chip2 = try #require(chips.first { $0.tabID == tab2ID })

        let chip1Point = chip1.convert(NSPoint(x: 24, y: chip1.bounds.midY), to: nil)
        #expect(mounted.rootView.hitTest(chip1Point) === chip1)
        await sendLeftClick(at: chip1Point, in: mounted.window)
        #expect(state.activeTabID == tab1ID)

        let chip2Point = chip2.convert(NSPoint(x: 24, y: chip2.bounds.midY), to: nil)
        #expect(mounted.rootView.hitTest(chip2Point) === chip2)
        await sendLeftClick(at: chip2Point, in: mounted.window)
        #expect(state.activeTabID == tab2ID)

        await sendLeftClick(at: chip1Point, in: mounted.window)
        #expect(state.activeTabID == tab1ID)
    }

    @MainActor
    private func verifyClosingOldAndInactiveTabs(
        tabIDs: [UUID],
        state: AppState,
        mounted: MountedTestWindow
    ) async throws {
        let (tab1ID, tab2ID, tab3ID) = (tabIDs[0], tabIDs[1], tabIDs[2])
        let chips = collectViews(ofType: WorkspaceTabChipView.self, in: mounted.rootView)
        let chip1 = try #require(chips.first { $0.tabID == tab1ID })
        let close1Point = chip1.closeButton.convert(
            NSPoint(x: chip1.closeButton.bounds.midX, y: chip1.closeButton.bounds.midY),
            to: nil
        )
        #expect(mounted.rootView.hitTest(close1Point) === chip1.closeButton)
        chip1.closeButton.performClick(nil)
        await pumpLayout(window: mounted.window, hosting: mounted.hosting)
        #expect(state.workspaceTabs.count == 2)
        #expect(!state.workspaceTabs.contains { $0.id == tab1ID })
        #expect(state.activeTabID == tab2ID)

        let updatedChips = collectViews(ofType: WorkspaceTabChipView.self, in: mounted.rootView)
        let chip3 = try #require(updatedChips.first { $0.tabID == tab3ID })
        let close3Point = chip3.closeButton.convert(
            NSPoint(x: chip3.closeButton.bounds.midX, y: chip3.closeButton.bounds.midY),
            to: nil
        )
        #expect(mounted.rootView.hitTest(close3Point) === chip3.closeButton)
        chip3.closeButton.performClick(nil)
        await pumpLayout(window: mounted.window, hosting: mounted.hosting)
        #expect(state.workspaceTabs.count == 1)
        #expect(state.workspaceTabs[0].id == tab2ID)
        #expect(state.activeTabID == tab2ID)
    }

    @MainActor
    private func pumpLayout(window: NSWindow, hosting: NSViewController) async {
        for _ in 0 ..< 4 {
            window.layoutIfNeeded()
            hosting.view.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    @MainActor
    private func sendLeftClick(at windowPoint: NSPoint, in window: NSWindow) async {
        let now = ProcessInfo.processInfo.systemUptime
        if let downEvent = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: windowPoint,
            modifierFlags: [],
            timestamp: now,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1.0
        ), let upEvent = NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: windowPoint,
            modifierFlags: [],
            timestamp: now + 0.01,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 2,
            clickCount: 1,
            pressure: 0.0
        ) {
            window.sendEvent(downEvent)
            window.sendEvent(upEvent)
        }
        try? await Task.sleep(for: .milliseconds(50))
    }

    @MainActor
    private func collectViews<T: NSView>(ofType _: T.Type, in root: NSView) -> [T] {
        var matches: [T] = []
        if let typed = root as? T {
            matches.append(typed)
        }
        for sub in root.subviews {
            matches.append(contentsOf: collectViews(ofType: T.self, in: sub))
        }
        return matches
    }

    @MainActor
    private func findDetailColumnMinX(in root: NSView) -> CGFloat? {
        for sub in root.subviews {
            if String(describing: type(of: sub)).contains("NSSplitView"), sub.subviews.count >= 2 {
                let wrappers = sub.subviews.filter {
                    String(describing: type(of: $0)).contains("_NSSplitViewItemViewWrapper")
                }
                if wrappers.count >= 2 {
                    return wrappers[1].convert(wrappers[1].bounds, to: root).minX
                }
            }
            if let found = findDetailColumnMinX(in: sub) {
                return found
            }
        }
        return nil
    }
}
