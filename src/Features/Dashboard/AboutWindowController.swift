import AppKit
import SparkleDesignSystem
import SwiftUI

/// Manages a standalone resizable macOS window hosting the SparkNotePad-inspired `AboutView`.
@MainActor
final class AboutWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func present(appState: AppState) {
        if let existing = window {
            existing.title = appState.strings.t("nav.about")
            SparkleWindowConfigurator.SparkleWindowProbeView.configure(
                window: existing,
                palette: appState.activePalette,
                allowFullScreen: true
            )
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let rootView = AboutView(appState: appState)
        let hostingController = NSHostingController(rootView: rootView)
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = appState.strings.t("nav.about")
        newWindow.minSize = NSSize(width: 640, height: 480)
        newWindow.collectionBehavior = [.fullScreenPrimary]
        SparkleWindowConfigurator.SparkleWindowProbeView.configure(
            window: newWindow,
            palette: appState.activePalette,
            allowFullScreen: true
        )
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
