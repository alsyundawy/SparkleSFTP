import AppKit
import SwiftUI

/// Configures the hosting macOS `NSWindow` with reliable Close/Minimize/Zoom controls and active palette chrome.
public struct SparkleWindowConfigurator: NSViewRepresentable {
    public let palette: SparkleThemePalette
    public let allowFullScreen: Bool
    public let onWindowResolved: (@MainActor (NSWindow) -> Void)?

    public init(
        palette: SparkleThemePalette,
        allowFullScreen: Bool = true,
        onWindowResolved: (@MainActor (NSWindow) -> Void)? = nil
    ) {
        self.palette = palette
        self.allowFullScreen = allowFullScreen
        self.onWindowResolved = onWindowResolved
    }

    public func makeNSView(context _: Context) -> SparkleWindowProbeView {
        let view = SparkleWindowProbeView(frame: .zero)
        view.palette = palette
        view.allowFullScreen = allowFullScreen
        view.onWindowResolved = onWindowResolved
        return view
    }

    public func updateNSView(_ nsView: SparkleWindowProbeView, context _: Context) {
        nsView.palette = palette
        nsView.allowFullScreen = allowFullScreen
        nsView.onWindowResolved = onWindowResolved
        nsView.applyWindowConfiguration()
    }

    @MainActor
    public final class SparkleWindowProbeView: NSView {
        var palette: SparkleThemePalette = SparkleThemeCatalog.defaultLight
        var allowFullScreen = true
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
                || Self.needsWindowControlsEnforcement(window)
            guard needsChromeUpdate else { return }
            isConfiguring = true
            defer { isConfiguring = false }
            lastConfiguredWindowNumber = window.windowNumber
            lastConfiguredPalette = palette
            onWindowResolved?(window)
            Self.configure(window: window, palette: palette, allowFullScreen: allowFullScreen)
        }

        private func installWindowObservers() {
            guard let window else {
                observerBox.clear()
                return
            }

            let names: [Notification.Name] = [
                NSWindow.didBecomeKeyNotification,
                NSWindow.didUpdateNotification
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
                              Self.needsWindowControlsEnforcement(currentWindow)
                        else { return }
                        probe.applyWindowConfiguration()
                    }
                }
                nextTokens.append(token)
            }
            observerBox.replace(with: nextTokens)
        }

        private static func needsWindowControlsEnforcement(_ window: NSWindow) -> Bool {
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

        public static func configure(
            window: NSWindow,
            palette: SparkleThemePalette,
            allowFullScreen: Bool = true
        ) {
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
            for buttonKind: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
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
