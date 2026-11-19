import AppKit
import SparkleCore
import SparkleDesignSystem
import SparkleFileManager
import SwiftUI

/// High-performance AppKit NSTableView wrapped for SwiftUI with strict cell dequeue reuse (MEM-004).
public struct FilePaneTableView: NSViewRepresentable {
    public let files: [RemoteFile]
    @Binding public var selectedIDs: Set<String>
    public let isLocalPane: Bool
    public let strings: AppStrings
    public let palette: SparkleThemePalette
    public let onActivateRow: (RemoteFile) -> Void
    public let onQuickLookRow: ((RemoteFile) -> Void)?
    public let onGoParent: (() -> Void)?
    public let onSortColumn: (FileSortField) -> Void
    public let onFocusPane: () -> Void
    public let onContextAction: (FilePaneContextAction, RemoteFile?) -> Void

    public init(
        files: [RemoteFile],
        selectedIDs: Binding<Set<String>>,
        isLocalPane: Bool = true,
        strings: AppStrings = AppStrings(),
        palette: SparkleThemePalette = SparkleThemeCatalog.defaultLight,
        onActivateRow: @escaping (RemoteFile) -> Void,
        onQuickLookRow: ((RemoteFile) -> Void)? = nil,
        onGoParent: (() -> Void)? = nil,
        onSortColumn: @escaping (FileSortField) -> Void,
        onFocusPane: @escaping () -> Void,
        onContextAction: @escaping (FilePaneContextAction, RemoteFile?) -> Void = { _, _ in }
    ) {
        self.files = files
        _selectedIDs = selectedIDs
        self.isLocalPane = isLocalPane
        self.strings = strings
        self.palette = palette
        self.onActivateRow = onActivateRow
        self.onQuickLookRow = onQuickLookRow
        self.onGoParent = onGoParent
        self.onSortColumn = onSortColumn
        self.onFocusPane = onFocusPane
        self.onContextAction = onContextAction
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true

        let tableView = createTableView(context: context)
        configureColumns(on: tableView)

        scrollView.documentView = tableView
        tableView.menu = context.coordinator.buildContextMenu()
        context.coordinator.cachedLocaleCode = strings.localeCode
        context.coordinator.scrollView = scrollView
        context.coordinator.tableView = tableView
        context.coordinator.installFocusObserver()
        context.coordinator.applyTheme(palette)
        return scrollView
    }

    private func createTableView(context: Context) -> InteractiveFileTableView {
        let tableView = InteractiveFileTableView()
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.gridStyleMask = .solidHorizontalGridLineMask
        tableView.allowsMultipleSelection = true
        tableView.allowsEmptySelection = true
        tableView.allowsTypeSelect = true
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.rowHeight = 22
        tableView.target = context.coordinator
        tableView.doubleAction = #selector(Coordinator.handleDoubleClick(_:))
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        wireTableCallbacks(tableView, coordinator: context.coordinator)
        return tableView
    }

    private func wireTableCallbacks(_ tableView: InteractiveFileTableView, coordinator: Coordinator) {
        tableView.onActivateSelected = { [weak coordinator] in coordinator?.activateCurrentSelection() }
        tableView.onQuickLookSelected = { [weak coordinator] in coordinator?.quickLookCurrentSelection() }
        tableView.onGoParent = { [weak coordinator] in coordinator?.parent.onGoParent?() }
        tableView.onFocusRequested = { [weak coordinator] in coordinator?.parent.onFocusPane() }
        tableView.onSwitchPane = { [weak tableView, isLocalPane] in
            guard let window = tableView?.window else { return }
            NotificationCenter.default.post(
                name: .sparklePaneFocusRequested,
                object: window,
                userInfo: ["isLocal": !isLocalPane]
            )
        }
        tableView.onRightClickSelectRow = { [weak coordinator] in coordinator?.selectRowForContextMenu($0) }
        tableView.onContextActionShortcut = { [weak coordinator] in coordinator?.triggerContextAction($0) }
        tableView.onDropFiles = { [weak coordinator] urls in coordinator?.handleDroppedURLs(urls) }
    }

    public static func dismantleNSView(_: NSScrollView, coordinator: Coordinator) {
        coordinator.removeFocusObserver()
    }

    private func configureColumns(on tableView: NSTableView) {
        let columns: [FilePaneColumnSpec] = [
            FilePaneColumnSpec(identifier: "name", title: strings.t("pane.name"), width: 240),
            FilePaneColumnSpec(identifier: "size", title: strings.t("pane.size"), width: 80),
            FilePaneColumnSpec(identifier: "modified", title: strings.t("pane.modified"), width: 140),
            FilePaneColumnSpec(identifier: "permissions", title: strings.t("pane.permissions"), width: 90)
        ]
        for spec in columns {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(spec.identifier))
            column.title = spec.title
            column.width = spec.width
            column.minWidth = 60
            tableView.addTableColumn(column)
        }
    }

    public func updateNSView(_: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tableView = context.coordinator.tableView else { return }
        if context.coordinator.cachedLocaleCode != strings.localeCode {
            context.coordinator.updateLocalizedHeadersAndMenu(for: tableView)
        }
        let themeChanged = context.coordinator.cachedPalette != palette
        if themeChanged {
            context.coordinator.applyTheme(palette)
        }
        let filesChanged = context.coordinator.cachedFiles != files
        if context.coordinator.isMenuOpen {
            if filesChanged {
                context.coordinator.cachedFiles = files
                context.coordinator.deferredReload = true
            }
            return
        }
        if filesChanged || themeChanged {
            context.coordinator.applyFilesUpdate(files: files, tableView: tableView, themeChanged: themeChanged)
            context.coordinator.isProgrammaticUpdate = true
            context.coordinator.syncSelectionToTableView()
            context.coordinator.isProgrammaticUpdate = false
        } else if context.coordinator.lastSyncedSelection != selectedIDs {
            context.coordinator.isProgrammaticUpdate = true
            context.coordinator.syncSelectionToTableView()
            context.coordinator.isProgrammaticUpdate = false
        }
    }
}
