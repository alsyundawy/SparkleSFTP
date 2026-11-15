import AppKit
import SwiftUI

/// Configures the hosting macOS `NSWindow` with reliable Close/Minimize/Zoom controls and active palette chrome.
public struct SparkleWindowConfigurator: NSViewRepresentable {
    public let palette: SparkleThemePalette
    public let allowFullScreen: Bool
    public let allowResize: Bool
    public let onWindowResolved: (@MainActor (NSWindow) -> Void)?

    public init(
        palette: SparkleThemePalette,
        allowFullScreen: Bool = true,
        allowResize: Bool = true,
        onWindowResolved: (@MainActor (NSWindow) -> Void)? = nil
    ) {
        self.palette = palette
        self.allowFullScreen = allowFullScreen
        self.allowResize = allowResize
        self.onWindowResolved = onWindowResolved
    }

    public func makeNSView(context _: Context) -> SparkleWindowProbeView {
        let view = SparkleWindowProbeView(frame: .zero)
        view.palette = palette
        view.allowFullScreen = allowFullScreen
        view.allowResize = allowResize
        view.onWindowResolved = onWindowResolved
        return view
    }

    public func updateNSView(_ nsView: SparkleWindowProbeView, context _: Context) {
        nsView.palette = palette
        nsView.allowFullScreen = allowFullScreen
        nsView.allowResize = allowResize
        nsView.onWindowResolved = onWindowResolved
        nsView.applyWindowConfiguration()
    }

    @MainActor
    public final class SparkleWindowProbeView: NSView {
        var palette: SparkleThemePalette = SparkleThemeCatalog.defaultLight
        var allowFullScreen = true
        var allowResize = true
        var onWindowResolved: (@MainActor (NSWindow) -> Void)?
        private let observerBox = WindowObserverBox()
        private var isConfiguring = false
        private var lastConfiguredPalette: SparkleThemePalette?
        private var lastConfiguredWindowNumber: Int = -1

        override public func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            lastConfiguredWindowNumber = -1
            installWindowObservers()
            applyWindowConfiguration()
            DispatchQueue.main.async { [weak self] in
                self?.applyWindowConfiguration()
            }
        }

        func applyWindowConfiguration() {
            guard !isConfiguring, let window else { return }
            let needsChromeUpdate = lastConfiguredWindowNumber != window.windowNumber
                || lastConfiguredPalette != palette
                || Self.needsWindowControlsEnforcement(window, allowResize: allowResize)
            guard needsChromeUpdate else { return }
            isConfiguring = true
            defer { isConfiguring = false }
            lastConfiguredWindowNumber = window.windowNumber
            lastConfiguredPalette = palette
            onWindowResolved?(window)
            Self.configure(
                window: window,
                palette: palette,
                allowFullScreen: allowFullScreen,
                allowResize: allowResize
            )
        }

        private func installWindowObservers() {
            guard let window else {
                observerBox.clear()
                return
            }

            let names: [Notification.Name] = [
                NSWindow.didBecomeKeyNotification,
                NSWindow.didResizeNotification
            ]
            var nextTokens: [any NSObjectProtocol] = []
            for name in names {
                let token = NotificationCenter.default.addObserver(
                    forName: name,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard let probe = self,
                              let currentWindow = probe.window,
                              Self.needsWindowControlsEnforcement(currentWindow, allowResize: probe.allowResize)
                        else { return }
                        probe.applyWindowConfiguration()
                    }
                }
                nextTokens.append(token)
            }
            observerBox.replace(with: nextTokens)
        }

        private static func needsWindowControlsEnforcement(_ window: NSWindow, allowResize: Bool) -> Bool {
            if allowResize {
                let requiredMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
                if !window.styleMask.isSuperset(of: requiredMask) {
                    return true
                }
                if window.maxSize.width < 10000 || window.maxSize.height < 10000 {
                    return true
                }
                for buttonKind: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
                    if let button = window.standardWindowButton(buttonKind), button.isHidden || !button.isEnabled {
                        return true
                    }
                }
            } else {
                let requiredMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
                if !window.styleMask.isSuperset(of: requiredMask) || window.styleMask.contains(.resizable) {
                    return true
                }
                let targetFrame = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: 760, height: 600)).size
                if window.maxSize.width > targetFrame.width || window.maxSize.height > targetFrame.height {
                    return true
                }
                for buttonKind: NSWindow.ButtonType in [.closeButton, .miniaturizeButton] {
                    if let button = window.standardWindowButton(buttonKind), button.isHidden || !button.isEnabled {
                        return true
                    }
                }
                if let zoomButton = window.standardWindowButton(.zoomButton), zoomButton.isEnabled {
                    return true
                }
            }
            return isTitlebarCoveredByContent(in: window)
        }

        private static func isTitlebarCoveredByContent(in window: NSWindow) -> Bool {
            guard let contentView = window.contentView,
                  let themeFrame = contentView.superview,
                  let titlebarContainer = window.standardWindowButton(.closeButton)?.superview?.superview,
                  titlebarContainer.superview === themeFrame,
                  let contentIndex = themeFrame.subviews.firstIndex(of: contentView),
                  let titlebarIndex = themeFrame.subviews.firstIndex(of: titlebarContainer)
            else {
                return false
            }
            return titlebarIndex < contentIndex
        }

        private static func configureStyleMaskAndBounds(
            window: NSWindow,
            allowResize: Bool,
            allowFullScreen: Bool
        ) {
            if allowResize {
                let requiredMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
                if !window.styleMask.isSuperset(of: requiredMask) {
                    window.styleMask.formUnion(requiredMask)
                }
                if window.maxSize.width < 10000 || window.maxSize.height < 10000 {
                    window.maxSize = NSSize(
                        width: CGFloat.greatestFiniteMagnitude,
                        height: CGFloat.greatestFiniteMagnitude
                    )
                }
                if allowFullScreen {
                    window.collectionBehavior.insert(.fullScreenPrimary)
                }
                if let zoomButton = window.standardWindowButton(.zoomButton) {
                    zoomButton.isHidden = false
                    zoomButton.isEnabled = true
                }
                window.showsResizeIndicator = true
            } else {
                let requiredMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
                if !window.styleMask.isSuperset(of: requiredMask) {
                    window.styleMask.formUnion(requiredMask)
                }
                window.styleMask.remove(.resizable)
                window.collectionBehavior.remove(.fullScreenPrimary)
                if let zoomButton = window.standardWindowButton(.zoomButton) {
                    zoomButton.isEnabled = false
                }
                window.showsResizeIndicator = false
                let targetFrame = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: 760, height: 600)).size
                if window.maxSize.width > targetFrame.width || window.maxSize.height > targetFrame.height {
                    window.maxSize = targetFrame
                }
                if window.minSize.width < targetFrame.width || window.minSize.height < targetFrame.height {
                    window.minSize = targetFrame
                }
            }
        }

        public static func configure(
            window: NSWindow,
            palette: SparkleThemePalette,
            allowFullScreen: Bool = true,
            allowResize: Bool = true
        ) {
            configureStyleMaskAndBounds(window: window, allowResize: allowResize, allowFullScreen: allowFullScreen)

            for buttonKind: NSWindow.ButtonType in [.closeButton, .miniaturizeButton] {
                if let button = window.standardWindowButton(buttonKind) {
                    button.isHidden = false
                    button.isEnabled = true
                }
            }

            if isTitlebarCoveredByContent(in: window),
               let themeFrame = window.contentView?.superview,
               let titlebarContainer = window.standardWindowButton(.closeButton)?.superview?.superview {
                themeFrame.addSubview(titlebarContainer, positioned: .above, relativeTo: nil)
            }
            window.backgroundColor = NSColor(hex: palette.windowHex)
            window.appearance = NSAppearance(named: palette.isDark ? .darkAqua : .aqua)
        }
    }
}

private final class WindowObserverBox: @unchecked Sendable { // JUSTIFICATION: Tokens guarded by NSLock.
    private let lock = NSLock()
    private var tokens: [any NSObjectProtocol] = []

    deinit {
        clear()
    }

    func replace(with nextTokens: [any NSObjectProtocol]) {
        let old = lock.withLock {
            let previous = tokens
            tokens = nextTokens
            return previous
        }
        for observer in old {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func clear() {
        replace(with: [])
    }
}
