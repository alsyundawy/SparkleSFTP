import AppKit

/// Manages the dedicated macOS standalone terminal window (iTerm2-style tabs and split panes).
@MainActor
final class StandaloneTerminalWindowController {
    private let host = ManagedWindowController(
        descriptor: ManagedWindowDescriptor(
            identifier: NSUserInterfaceItemIdentifier("sparkle.standaloneTerminal"),
            defaultSize: NSSize(width: 1020, height: 660),
            minSize: NSSize(width: 640, height: 400),
            allowFullScreen: true,
            shareAcrossAppStates: true
        )
    )

    func present(appState: AppState) {
        host.present(title: appState.strings.t("nav.standaloneTerminal"), appState: appState) {
            StandaloneTerminalWindowView(appState: appState, manager: appState.standaloneTerminalManager)
        }
    }
}
