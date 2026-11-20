import AppKit
import SparkleDesignSystem
import SwiftUI

struct ManagedWindowDescriptor {
    let identifier: NSUserInterfaceItemIdentifier
    let defaultSize: NSSize
    let minSize: NSSize
    let maxSize: NSSize?
    let allowFullScreen: Bool
    let isResizable: Bool
    let shareAcrossAppStates: Bool

    init(
        identifier: NSUserInterfaceItemIdentifier,
        defaultSize: NSSize,
        minSize: NSSize,
        maxSize: NSSize? = nil,
        allowFullScreen: Bool = true,
        isResizable: Bool = true,
        shareAcrossAppStates: Bool = true
    ) {
        self.identifier = identifier
        self.defaultSize = defaultSize
        self.minSize = minSize
        self.maxSize = maxSize
        self.allowFullScreen = allowFullScreen
        self.isResizable = isResizable
        self.shareAcrossAppStates = shareAcrossAppStates
    }
}

/// Shared AppKit window host for standalone SparkleSFTP utility and document windows.
/// Uses `sizingOptions = [.minSize]` so SwiftUI tab switches never jump window dimensions
/// while Close, Minimize, and Maximize/Zoom traffic-light controls remain active.
@MainActor
final class ManagedWindowController: NSObject, NSWindowDelegate {
    private let descriptor: ManagedWindowDescriptor
    private var window: NSWindow?
    var onWindowWillClose: (@MainActor () -> Void)?

    var isVisible: Bool {
        window?.isVisible ?? false
    }

    func close() {
        window?.close()
        window = nil
    }

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
            presentExistingWindow(existing, title: title, appState: appState)
            return
        }

        let hostingController = NSHostingController(rootView: content())
        hostingController.sizingOptions = [.minSize]
        let newWindow = makeWindow(title: title, appState: appState, hostingController: hostingController)
        window = newWindow
        newWindow.orderFrontRegardless()
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func presentExistingWindow(_ existing: NSWindow, title: String, appState: AppState) {
        existing.title = title
        if !descriptor.isResizable {
            let bounds = NSRect(origin: .zero, size: descriptor.defaultSize)
            let targetFrame = existing.frameRect(forContentRect: bounds).size
            existing.maxSize = targetFrame
            existing.minSize = targetFrame
        }
        SparkleWindowConfigurator.SparkleWindowProbeView.configure(
            window: existing,
            palette: appState.activePalette,
            allowFullScreen: descriptor.allowFullScreen,
            allowResize: descriptor.isResizable
        )
        if existing.isMiniaturized {
            existing.deminiaturize(nil)
        }
        existing.setIsVisible(true)
        existing.orderFrontRegardless()
        existing.makeKeyAndOrderFront(nil)
        existing.makeMain()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func instantiateWindow(styleMask: NSWindow.StyleMask) -> NSWindow {
        if descriptor.isResizable {
            return NSWindow(
                contentRect: NSRect(origin: .zero, size: descriptor.defaultSize),
                styleMask: styleMask,
                backing: .buffered,
                defer: false
            )
        }
        let fixed = FixedManagedWindow(
            contentRect: NSRect(origin: .zero, size: descriptor.defaultSize),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        fixed.fixedContentSize = descriptor.defaultSize
        return fixed
    }

    private func makeWindow(
        title: String,
        appState: AppState,
        hostingController: NSViewController
    ) -> NSWindow {
        let styleMask: NSWindow.StyleMask = descriptor.isResizable
            ? [.titled, .closable, .miniaturizable, .resizable]
            : [.titled, .closable, .miniaturizable]

        let newWindow = instantiateWindow(styleMask: styleMask)
        newWindow.identifier = descriptor.identifier
        newWindow.title = title
        newWindow.minSize = descriptor.minSize
        if let max = descriptor.maxSize {
            newWindow.maxSize = max
        } else if !descriptor.isResizable {
            newWindow.maxSize = descriptor.defaultSize
        }
        newWindow.showsResizeIndicator = descriptor.isResizable
        if descriptor.allowFullScreen, descriptor.isResizable {
            newWindow.collectionBehavior = [.fullScreenPrimary]
        }
        SparkleWindowConfigurator.SparkleWindowProbeView.configure(
            window: newWindow,
            palette: appState.activePalette,
            allowFullScreen: descriptor.allowFullScreen,
            allowResize: descriptor.isResizable
        )
        newWindow.isReleasedWhenClosed = false
        newWindow.contentViewController = hostingController
        newWindow.setContentSize(descriptor.defaultSize)
        if !descriptor.isResizable {
            let bounds = NSRect(origin: .zero, size: descriptor.defaultSize)
            let targetFrame = newWindow.frameRect(forContentRect: bounds).size
            newWindow.maxSize = targetFrame
            newWindow.minSize = targetFrame
            newWindow.showsResizeIndicator = false
        }
        newWindow.center()
        newWindow.delegate = self
        return newWindow
    }

    private func activeOrSharedWindow() -> NSWindow? {
        if let existing = window, existing.isVisible {
            return existing
        }
        guard descriptor.shareAcrossAppStates else { return nil }
        return NSApp?.windows.first {
            $0.identifier == descriptor.identifier && $0.isVisible
        }
    }

    func windowWillClose(_: Notification) {
        onWindowWillClose?()
        window = nil
    }
}

final class FixedManagedWindow: NSWindow {
    var fixedContentSize: NSSize = .zero

    override var maxSize: NSSize {
        get {
            guard fixedContentSize.width > 0, fixedContentSize.height > 0 else { return super.maxSize }
            return frameRect(forContentRect: NSRect(origin: .zero, size: fixedContentSize)).size
        }
        set {
            if fixedContentSize.width == 0 {
                super.maxSize = newValue
            }
        }
    }

    override var minSize: NSSize {
        get {
            guard fixedContentSize.width > 0, fixedContentSize.height > 0 else { return super.minSize }
            return frameRect(forContentRect: NSRect(origin: .zero, size: fixedContentSize)).size
        }
        set {
            if fixedContentSize.width == 0 {
                super.minSize = newValue
            }
        }
    }
}
