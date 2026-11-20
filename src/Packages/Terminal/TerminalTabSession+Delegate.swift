import AppKit
import Foundation
import SwiftTerm

extension TerminalTabSession: TerminalViewDelegate {
    public nonisolated func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        guard newCols >= 10, newRows >= 2 else { return }
        Task { @MainActor [weak self] in
            self?.resizePTY(cols: newCols, rows: newRows)
        }
    }

    public nonisolated func setTerminalTitle(source: TerminalView, title: String) {
        Task { @MainActor [weak self] in
            self?.updateTitle(title)
        }
    }

    public nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        Task { @MainActor [weak self] in
            self?.updateRemoteWorkingDirectory(directory)
        }
    }

    public nonisolated func send(source: TerminalView, data: ArraySlice<UInt8>) {
        let bytes = Array(data)
        Task { @MainActor [weak self] in
            self?.sendInput(bytes[...])
        }
    }

    public nonisolated func scrolled(source: TerminalView, position: Double) {}

    public nonisolated func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        guard let url = URL(string: link),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http"
        else { return }
        Task { @MainActor in
            NSWorkspace.shared.open(url)
        }
    }

    public nonisolated func bell(source: TerminalView) {
        Task { @MainActor in
            NSSound.beep()
        }
    }

    public nonisolated func clipboardCopy(source: TerminalView, content: Data) {
        guard let text = String(data: content, encoding: .utf8) else { return }
        Task { @MainActor in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }

    public nonisolated func clipboardRead(source: TerminalView) -> Data? {
        nil
    }

    public nonisolated func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}

    public nonisolated func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}
