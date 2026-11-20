import AppKit

/// Manages the dedicated macOS enlarged internal terminal window (1020x660 pt),
/// directly hosting the authenticated Swift-NIO-SSH interactive shell with zero credential prompts.
@MainActor
final class EnlargedTerminalWindowController {
    private let host = ManagedWindowController(
        descriptor: ManagedWindowDescriptor(
            identifier: NSUserInterfaceItemIdentifier("sparkle.enlargedTerminal"),
            defaultSize: NSSize(width: 1020, height: 660),
            minSize: NSSize(width: 640, height: 400),
            allowFullScreen: true,
            shareAcrossAppStates: true
        )
    )

    private weak var boundAppState: AppState?

    init() {
        host.onWindowWillClose = { [weak self] in
            self?.boundAppState?.isTerminalEnlarged = false
        }
    }

    func present(appState: AppState) {
        boundAppState = appState
        let title: String
        if let session = appState.currentSession {
            title = "\(session.profile.name) — \(appState.strings.t("nav.enlargedTerminal"))"
        } else {
            title = appState.strings.t("nav.enlargedTerminal")
        }
        host.present(title: title, appState: appState) {
            EnlargedTerminalWindowView(appState: appState)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if let active = appState.terminalManager.selectedSession ?? appState.terminalManager.sessions.first {
                let view = active.getOrCreateTerminalView()
                view.terminal.updateFullScreen()
                view.feed(text: "")
                view.setNeedsDisplay(view.bounds)
                if let window = view.window {
                    window.makeFirstResponder(view)
                }
            }
        }
    }

    func close() {
        host.close()
    }

    var isVisible: Bool {
        host.isVisible
    }
}
