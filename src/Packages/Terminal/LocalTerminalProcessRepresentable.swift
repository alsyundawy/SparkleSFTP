import AppKit
import SwiftTerm
import SwiftUI

/// SwiftUI `NSViewRepresentable` wrapper embedding a persistent `SwiftTerm.LocalProcessTerminalView`
/// managed by `StandaloneTerminalManager` so iTerm2-style split operations preserve live shells.
public struct LocalTerminalProcessRepresentable: NSViewRepresentable {
    public let pane: StandaloneTerminalPane
    @ObservedObject public var manager: StandaloneTerminalManager
    public let themeColors: TerminalThemeColors?

    public init(
        pane: StandaloneTerminalPane,
        manager: StandaloneTerminalManager,
        themeColors: TerminalThemeColors? = nil
    ) {
        self.pane = pane
        self.manager = manager
        self.themeColors = themeColors
    }

    public func makeCoordinator() -> Coordinator {
        let paneID = pane.id
        weak let weakManager = manager
        return Coordinator(
            onTitleChange: { title in
                Task { @MainActor in weakManager?.updatePaneTitle(title, for: paneID) }
            },
            onDirectoryChange: { directory in
                Task { @MainActor in weakManager?.updatePaneDirectory(directory, for: paneID) }
            },
            onProcessTerminated: { exitCode in
                Task { @MainActor in weakManager?.markPaneTerminated(paneID: paneID, exitCode: exitCode) }
            }
        )
    }

    public func makeNSView(context: Context) -> LocalProcessTerminalView {
        let view = manager.existingOrCreateView(
            for: pane,
            colors: themeColors,
            delegate: context.coordinator
        )
        view.removeFromSuperview()
        context.coordinator.cachedThemeColors = themeColors
        context.coordinator.cachedFontSize = manager.fontSize
        return view
    }

    public func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        nsView.processDelegate = context.coordinator
        if context.coordinator.cachedThemeColors != themeColors {
            context.coordinator.cachedThemeColors = themeColors
            TerminalThemeColors.apply(themeColors, to: nsView)
        }
        if context.coordinator.cachedFontSize != manager.fontSize {
            context.coordinator.cachedFontSize = manager.fontSize
            nsView.font = NSFont.monospacedSystemFont(ofSize: manager.fontSize, weight: .regular)
        }
    }

    public final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        private let onTitleChange: @Sendable (String) -> Void
        private let onDirectoryChange: @Sendable (String?) -> Void
        private let onProcessTerminated: @Sendable (Int32?) -> Void

        @MainActor var cachedThemeColors: TerminalThemeColors?
        @MainActor var cachedFontSize: CGFloat = 13.0

        init(
            onTitleChange: @escaping @Sendable (String) -> Void,
            onDirectoryChange: @escaping @Sendable (String?) -> Void,
            onProcessTerminated: @escaping @Sendable (Int32?) -> Void
        ) {
            self.onTitleChange = onTitleChange
            self.onDirectoryChange = onDirectoryChange
            self.onProcessTerminated = onProcessTerminated
        }

        public func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
            _ = (source, newCols, newRows)
        }

        public func setTerminalTitle(source _: LocalProcessTerminalView, title: String) {
            onTitleChange(title)
        }

        public func hostCurrentDirectoryUpdate(source _: TerminalView, directory: String?) {
            onDirectoryChange(directory)
        }

        public func processTerminated(source _: TerminalView, exitCode: Int32?) {
            onProcessTerminated(exitCode)
        }
    }
}
