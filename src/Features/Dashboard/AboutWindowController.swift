import AppKit

/// Manages a standalone resizable macOS window hosting the SparkNotePad-inspired `AboutView`.
@MainActor
final class AboutWindowController {
    private let host = ManagedWindowController(
        descriptor: ManagedWindowDescriptor(
            identifier: NSUserInterfaceItemIdentifier("sparkle.about"),
            defaultSize: NSSize(width: 720, height: 560),
            minSize: NSSize(width: 720, height: 560),
            allowFullScreen: true,
            shareAcrossAppStates: true
        )
    )

    func present(appState: AppState) {
        host.present(title: appState.strings.t("nav.about"), appState: appState) {
            AboutView(appState: appState)
        }
    }
}
