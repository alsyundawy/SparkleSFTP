import AppKit
import Foundation
import SparkleNetworking
import SwiftTerm
import SwiftUI

/// SwiftUI NSViewRepresentable wrapper over `SwiftTerm.TerminalView` with strict PTY delegate teardown (MEM-002).
public struct TerminalViewRepresentable: NSViewRepresentable {
    public let session: TerminalTabSession

    public init(session: TerminalTabSession) {
        self.session = session
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    public func makeNSView(context: Context) -> TerminalView {
        let view = TerminalView(frame: .zero)
        view.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        view.configureNativeColors()
        view.optionAsMetaKey = true
        view.allowMouseReporting = true
        view.terminalDelegate = context.coordinator
        session.attachTerminalView(view)
        return view
    }

    public func updateNSView(_ nsView: TerminalView, context: Context) {
        if nsView.terminalDelegate !== context.coordinator {
            nsView.terminalDelegate = context.coordinator
        }
    }

    public static func dismantleNSView(_ nsView: TerminalView, coordinator: Coordinator) {
        nsView.terminalDelegate = nil
        coordinator.teardown()
    }

    @MainActor
    public final class Coordinator: NSObject, @MainActor TerminalViewDelegate {
        private weak var session: TerminalTabSession?

        init(session: TerminalTabSession) {
            self.session = session
        }

        func teardown() {
            session = nil
        }

        public func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            session?.resizePTY(cols: newCols, rows: newRows)
        }

        public func setTerminalTitle(source: TerminalView, title: String) {
            session?.updateTitle(title)
        }

        public func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
            session?.updateRemoteWorkingDirectory(directory)
        }

        public func send(source: TerminalView, data: ArraySlice<UInt8>) {
            session?.sendInput(data)
        }

        public func scrolled(source: TerminalView, position: Double) {}

        public func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
            guard let url = URL(string: link),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "https" || scheme == "http"
            else {
                return
            }
            NSWorkspace.shared.open(url)
        }

        public func bell(source: TerminalView) {
            NSSound.beep()
        }

        public func clipboardCopy(source: TerminalView, content: Data) {
            guard let text = String(data: content, encoding: .utf8) else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }

        public func clipboardRead(source: TerminalView) -> Data? {
            // Security default: deny arbitrary OSC 52 clipboard reads from untrusted remote PTYs.
            nil
        }

        public func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}

        public func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }
}
