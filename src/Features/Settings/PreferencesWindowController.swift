import AppKit

/// Manages a standalone resizable macOS Preferences window (`Cmd+,`) with active traffic lights
/// and fixed tab-switch geometry replacing SwiftUI's non-zoomable `Settings` scene.
@MainActor
final class PreferencesWindowController {
    private let host = ManagedWindowController(
        descriptor: ManagedWindowDescriptor(
            identifier: NSUserInterfaceItemIdentifier("sparkle.preferences"),
            defaultSize: NSSize(width: 760, height: 600),
            minSize: NSSize(width: 760, height: 600),
            allowFullScreen: true,
            shareAcrossAppStates: true
        )
    )

    func present(appState: AppState) {
        host.present(title: appState.strings.t("nav.settings"), appState: appState) {
            PreferencesView(appState: appState)
        }
    }
}
