import AppKit
import SwiftUI

/// Configures the hosting macOS `NSWindow` with reliable Close/Minimize/Zoom controls and active palette chrome.
public struct SparkleWindowConfigurator: NSViewRepresentable {
    public let palette: SparkleThemePalette
    public let allowFullScreen: Bool

    public init(palette: SparkleThemePalette, allowFullScreen: Bool = true) {
        self.palette = palette
        self.allowFullScreen = allowFullScreen
    }

    public func makeNSView(context _: Context) -> SparkleWindowProbeView {
        let view = SparkleWindowProbeView(frame: .zero)
        view.palette = palette
        view.allowFullScreen = allowFullScreen
        return view
    }

    public func updateNSView(_ nsView: SparkleWindowProbeView, context _: Context) {
        nsView.palette = palette
        nsView.allowFullScreen = allowFullScreen
        nsView.applyWindowConfiguration()
    }

    @MainActor
    public final class SparkleWindowProbeView: NSView {
        var palette: SparkleThemePalette = SparkleThemeCatalog.defaultLight
        var allowFullScreen = true

        override public func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyWindowConfiguration()
        }

        func applyWindowConfiguration() {
            guard let window else { return }
            Self.configure(window: window, palette: palette, allowFullScreen: allowFullScreen)
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
            if allowFullScreen {
                window.collectionBehavior.insert(.fullScreenPrimary)
            }
            for buttonKind: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
                if let button = window.standardWindowButton(buttonKind) {
                    button.isHidden = false
                    button.isEnabled = true
                }
            }
            window.backgroundColor = NSColor(hex: palette.windowHex)
            window.appearance = NSAppearance(named: palette.isDark ? .darkAqua : .aqua)
        }
    }
}
