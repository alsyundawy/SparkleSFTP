import AppKit

/// Manages a standalone resizable macOS window hosting `InternalEditorView`.
@MainActor
final class EditorWindowController {
    private let host = ManagedWindowController(
        descriptor: ManagedWindowDescriptor(
            identifier: NSUserInterfaceItemIdentifier("sparkle.editor"),
            defaultSize: NSSize(width: 900, height: 620),
            minSize: NSSize(width: 680, height: 420),
            allowFullScreen: true,
            shareAcrossAppStates: false
        )
    )

    func present(appState: AppState) {
        host.present(title: appState.strings.t("editor.windowTitle"), appState: appState) {
            InternalEditorView(appState: appState)
        }
    }
}
