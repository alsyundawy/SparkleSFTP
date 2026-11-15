import AppKit

/// Manages a standalone fixed-size macOS Preferences window (`Cmd+,`) with active Close/Minimize controls
/// and locked 760x600 geometry replacing SwiftUI's non-zoomable `Settings` scene.
@MainActor
final class PreferencesWindowController {
    private let host = ManagedWindowController(
        descriptor: ManagedWindowDescriptor(
            identifier: NSUserInterfaceItemIdentifier("sparkle.preferences"),
            defaultSize: NSSize(width: 760, height: 600),
            minSize: NSSize(width: 760, height: 600),
            maxSize: NSSize(width: 760, height: 600),
            allowFullScreen: false,
            isResizable: false,
            shareAcrossAppStates: true
        )
    )

    func present(appState: AppState) {
        host.present(title: appState.strings.t("nav.settings"), appState: appState) {
            PreferencesView(appState: appState)
        }
    }
}
