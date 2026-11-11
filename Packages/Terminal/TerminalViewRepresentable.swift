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
    public final class Coordinator: NSObject, TerminalViewDelegate {
        private weak var session: TerminalTabSession?

        init(session: TerminalTabSession) {
            self.session = session
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
