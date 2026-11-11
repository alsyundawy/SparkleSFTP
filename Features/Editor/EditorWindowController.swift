import AppKit
import SwiftUI

/// Manages a standalone resizable macOS window hosting `InternalEditorView`.
@MainActor
final class EditorWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func present(appState: AppState) {
        if let existing = window {
            existing.title = appState.strings.t("editor.windowTitle")
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let rootView = InternalEditorView(appState: appState)
        let hostingController = NSHostingController(rootView: rootView)
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = appState.strings.t("editor.windowTitle")
        newWindow.minSize = NSSize(width: 680, height: 420)
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        newWindow.contentViewController = hostingController
        newWindow.delegate = self
        window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_: Notification) {
        // Window stays cached (isReleasedWhenClosed = false) to preserve active tabs across reopen.
    }
}
