import AppKit
import SparkleDesignSystem
import SwiftUI

struct ManagedWindowDescriptor {
    let identifier: NSUserInterfaceItemIdentifier
    let defaultSize: NSSize
    let minSize: NSSize
    let allowFullScreen: Bool
    let shareAcrossAppStates: Bool
}

/// Shared AppKit window host for standalone SparkleSFTP utility and document windows.
/// Uses `sizingOptions = [.minSize]` so SwiftUI tab switches never jump window dimensions
/// while Close, Minimize, and Maximize/Zoom traffic-light controls remain active.
@MainActor
final class ManagedWindowController: NSObject, NSWindowDelegate {
    private let descriptor: ManagedWindowDescriptor
    private var window: NSWindow?

    init(descriptor: ManagedWindowDescriptor) {
        self.descriptor = descriptor
        super.init()
    }

    func present(
        title: String,
        appState: AppState,
        @ViewBuilder content: () -> some View
    ) {
        if let existing = activeOrSharedWindow() {
            existing.title = title
            SparkleWindowConfigurator.SparkleWindowProbeView.configure(
                window: existing,
                palette: appState.activePalette,
                allowFullScreen: descriptor.allowFullScreen
            )
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let hostingController = NSHostingController(rootView: content())
        hostingController.sizingOptions = [.minSize]

        let newWindow = NSWindow(
            contentRect: NSRect(origin: .zero, size: descriptor.defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        newWindow.identifier = descriptor.identifier
        newWindow.title = title
        newWindow.minSize = descriptor.minSize
        if descriptor.allowFullScreen {
            newWindow.collectionBehavior = [.fullScreenPrimary]
        }
        SparkleWindowConfigurator.SparkleWindowProbeView.configure(
            window: newWindow,
            palette: appState.activePalette,
            allowFullScreen: descriptor.allowFullScreen
        )
        newWindow.isReleasedWhenClosed = false
        newWindow.contentViewController = hostingController
        newWindow.setContentSize(descriptor.defaultSize)
        newWindow.center()
        newWindow.delegate = self
        window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
    }

    private func activeOrSharedWindow() -> NSWindow? {
        if let existing = window {
            return existing
        }
        guard descriptor.shareAcrossAppStates else { return nil }
        return NSApp?.windows.first {
            $0.identifier == descriptor.identifier && $0.isVisible
        }
    }

    func windowWillClose(_: Notification) {
        // Window stays cached (`isReleasedWhenClosed = false`) for instant reopen.
    }
}
