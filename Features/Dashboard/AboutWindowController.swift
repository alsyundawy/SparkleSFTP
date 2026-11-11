import AppKit
import SwiftUI

/// Manages a standalone resizable macOS window hosting the SparkNotePad-inspired `AboutView`.
@MainActor
final class AboutWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func present(appState: AppState) {
        if let existing = window {
            existing.title = appState.strings.t("nav.about")
            existing.backgroundColor = NSColor(hex: appState.activePalette.windowHex)
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let rootView = AboutView(appState: appState)
        let hostingController = NSHostingController(rootView: rootView)
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 540),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = appState.strings.t("nav.about")
        newWindow.backgroundColor = NSColor(hex: appState.activePalette.windowHex)
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        newWindow.contentViewController = hostingController
        newWindow.delegate = self
        window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_: Notification) {
        // Window stays cached cleanly for instant reopen across sessions.
    }
}
