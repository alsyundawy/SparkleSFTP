import AppKit
import Foundation
import SparkleNetworking
import SwiftTerm
import SwiftUI

/// Portable theme color bundle applied to AppKit `SwiftTerm.TerminalView` without adding DesignSystem coupling.
public struct TerminalThemeColors: Sendable, Equatable {
    public let backgroundHex: String
    public let foregroundHex: String
    public let caretHex: String
    public let selectionHex: String

    public init(backgroundHex: String, foregroundHex: String, caretHex: String, selectionHex: String) {
        self.backgroundHex = backgroundHex
        self.foregroundHex = foregroundHex
        self.caretHex = caretHex
        self.selectionHex = selectionHex
    }

    fileprivate var backgroundNSColor: NSColor {
        Self.nsColor(hex: backgroundHex, fallback: .textBackgroundColor)
    }

    fileprivate var foregroundNSColor: NSColor {
        Self.nsColor(hex: foregroundHex, fallback: .textColor)
    }

    fileprivate var caretNSColor: NSColor {
        Self.nsColor(hex: caretHex, fallback: .selectedControlColor)
    }

    fileprivate var selectionNSColor: NSColor {
        Self.nsColor(hex: selectionHex, fallback: .selectedControlColor).withAlphaComponent(0.32)
    }

    private static func nsColor(hex: String, fallback: NSColor) -> NSColor {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") {
            cleaned.removeFirst()
        }
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else {
            return fallback
        }
        let red = CGFloat((value >> 16) & 0xFF) / 255.0
        let green = CGFloat((value >> 8) & 0xFF) / 255.0
        let blue = CGFloat(value & 0xFF) / 255.0
        return NSColor(srgbRed: red, green: green, blue: blue, alpha: 1.0)
    }

    @MainActor
    static func apply(_ colors: TerminalThemeColors?, to view: TerminalView) {
        if let colors {
            view.nativeBackgroundColor = colors.backgroundNSColor
            view.nativeForegroundColor = colors.foregroundNSColor
            view.caretColor = colors.caretNSColor
            view.selectedTextBackgroundColor = colors.selectionNSColor
        } else {
            view.configureNativeColors()
        }
    }
}

/// SwiftUI NSViewRepresentable wrapper over `SwiftTerm.TerminalView` with strict PTY delegate teardown (MEM-002).
public struct TerminalViewRepresentable: NSViewRepresentable {
    public let session: TerminalTabSession
    public let themeColors: TerminalThemeColors?

    public init(session: TerminalTabSession, themeColors: TerminalThemeColors? = nil) {
        self.session = session
        self.themeColors = themeColors
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    public func makeNSView(context: Context) -> TerminalView {
        let view = TerminalView(frame: .zero, options: TerminalOptions(scrollback: 10000))
        view.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        applyTheme(themeColors, to: view)
        context.coordinator.cachedThemeColors = themeColors
        view.optionAsMetaKey = true
        view.allowMouseReporting = true
        view.terminalDelegate = context.coordinator
        session.attachTerminalView(view)
        return view
    }

    public func updateNSView(_ nsView: TerminalView, context: Context) {
        if context.coordinator.boundSession !== session {
            context.coordinator.rebind(to: session, terminalView: nsView)
        }
        if nsView.terminalDelegate !== context.coordinator {
            nsView.terminalDelegate = context.coordinator
        }
        if context.coordinator.cachedThemeColors != themeColors {
            context.coordinator.cachedThemeColors = themeColors
            applyTheme(themeColors, to: nsView)
        }
    }

    private func applyTheme(_ colors: TerminalThemeColors?, to view: TerminalView) {
        TerminalThemeColors.apply(colors, to: view)
    }

    public static func dismantleNSView(_ nsView: TerminalView, coordinator: Coordinator) {
        nsView.terminalDelegate = nil
        coordinator.teardown()
    }

    @MainActor
    public final class Coordinator: NSObject, TerminalViewDelegate {
        private weak var session: TerminalTabSession?
        var cachedThemeColors: TerminalThemeColors?

        var boundSession: TerminalTabSession? {
            session
        }

        init(session: TerminalTabSession) {
            self.session = session
        }

        func rebind(to newSession: TerminalTabSession, terminalView: TerminalView) {
            session = newSession
            newSession.attachTerminalView(terminalView)
        }

        func teardown() {
            session = nil
        }

        private nonisolated func runOnMain(_ work: @escaping @MainActor (Coordinator) -> Void) {
            if Thread.isMainThread {
                MainActor.assumeIsolated { work(self) }
            } else {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    MainActor.assumeIsolated { work(self) }
                }
            }
        }

        public nonisolated func sizeChanged(source _: TerminalView, newCols: Int, newRows: Int) {
            runOnMain { coordinator in
                coordinator.session?.resizePTY(cols: newCols, rows: newRows)
            }
        }

        public nonisolated func setTerminalTitle(source _: TerminalView, title: String) {
            runOnMain { coordinator in
                coordinator.session?.updateTitle(title)
            }
        }

        public nonisolated func hostCurrentDirectoryUpdate(source _: TerminalView, directory: String?) {
            runOnMain { coordinator in
                coordinator.session?.updateRemoteWorkingDirectory(directory)
            }
        }

        public nonisolated func send(source _: TerminalView, data: ArraySlice<UInt8>) {
            let bytes = Array(data)
            runOnMain { coordinator in
                coordinator.session?.sendInput(bytes[...])
            }
        }

        public nonisolated func scrolled(source _: TerminalView, position _: Double) {}

        public nonisolated func requestOpenLink(source _: TerminalView, link: String, params _: [String: String]) {
            guard let url = URL(string: link),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "https" || scheme == "http"
            else {
                return
            }
            runOnMain { _ in
                NSWorkspace.shared.open(url)
            }
        }

        public nonisolated func bell(source _: TerminalView) {
            runOnMain { _ in
                NSSound.beep()
            }
        }

        public nonisolated func clipboardCopy(source _: TerminalView, content: Data) {
            guard let text = String(data: content, encoding: .utf8) else { return }
            runOnMain { _ in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
        }

        public nonisolated func clipboardRead(source _: TerminalView) -> Data? {
            // Security default: deny arbitrary OSC 52 clipboard reads from untrusted remote PTYs.
            nil
        }

        public nonisolated func iTermContent(source _: TerminalView, content _: ArraySlice<UInt8>) {}

        public nonisolated func rangeChanged(source _: TerminalView, startY _: Int, endY _: Int) {}
    }
}
