import AppKit
import SparkleCore
import SparkleDesignSystem
import SparkleFileManager
import SwiftUI

public enum FilePaneContextAction: Int, Sendable {
    case open = 1
    case transfer = 2
    case quickLook = 3
    case edit = 4
    case rename = 5
    case permissions = 6
    case inspect = 7
    case newFolder = 8
    case delete = 9
    case openExternalApp = 10
    case configureEditor = 11
    case copyTo = 12
    case moveTo = 13
    case copyClipboard = 14
    case compareFiles = 15
    case compressAndUpload = 16
    case verifyChecksum = 17
    case customSSHCommand = 18
    case insertCommandLine = 19
    case copyFileNames = 20
    case copyFullPaths = 21
    case selectAll = 22
    case showInFinder = 23
}

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
        tableView.onActivateSelected = { [weak coordinator = context.coordinator] in
            coordinator?.activateCurrentSelection()
        }
        tableView.onQuickLookSelected = { [weak coordinator = context.coordinator] in
            coordinator?.quickLookCurrentSelection()
        }
        tableView.onGoParent = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onGoParent?()
        }
        tableView.onRightClickSelectRow = { [weak coordinator = context.coordinator] row in
            coordinator?.selectRowForContextMenu(row)
        }
        tableView.onContextActionShortcut = { [weak coordinator = context.coordinator] action in
            coordinator?.triggerContextAction(action)
        }

        configureColumns(on: tableView)

        scrollView.documentView = tableView
        tableView.menu = context.coordinator.buildContextMenu()
        context.coordinator.cachedLocaleCode = strings.localeCode
        context.coordinator.scrollView = scrollView
        context.coordinator.tableView = tableView
        context.coordinator.applyTheme(palette)
        return scrollView
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
        let filesChanged = context.coordinator.cachedFiles.count != files.count
            || context.coordinator.cachedFiles != files
        if filesChanged || themeChanged {
            context.coordinator.cachedFiles = files
            context.coordinator.isProgrammaticUpdate = true
            tableView.reloadData()
            context.coordinator.syncSelectionToTableView()
            context.coordinator.isProgrammaticUpdate = false
        } else if context.coordinator.lastSyncedSelection != selectedIDs {
            context.coordinator.isProgrammaticUpdate = true
            context.coordinator.syncSelectionToTableView()
            context.coordinator.isProgrammaticUpdate = false
        }
    }
}

public extension FilePaneTableView {
    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: FilePaneTableView
        var cachedFiles: [RemoteFile] = []
        var cachedPalette: SparkleThemePalette?
        var cachedLocaleCode: String = ""
        var lastSyncedSelection: Set<String> = []
        weak var scrollView: NSScrollView?
        weak var tableView: NSTableView?
        var isProgrammaticUpdate = false

        private static let folderSymbol = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil)
        private static let linkSymbol = NSImage(systemSymbolName: "link", accessibilityDescription: nil)
        private static let fileSymbol = NSImage(systemSymbolName: "doc", accessibilityDescription: nil)

        private static let byteFormatter: ByteCountFormatter = {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            return formatter
        }()

        private static let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            return formatter
        }()

        init(parent: FilePaneTableView) {
            self.parent = parent
            cachedFiles = parent.files
            lastSyncedSelection = parent.selectedIDs
        }

        func applyTheme(_ palette: SparkleThemePalette) {
            cachedPalette = palette
            let canvasColor = NSColor(hex: palette.canvasHex)
            scrollView?.backgroundColor = canvasColor
            tableView?.backgroundColor = canvasColor
            tableView?.gridColor = NSColor(hex: palette.borderHex).withAlphaComponent(0.32)
        }

        func updateLocalizedHeadersAndMenu(for tableView: NSTableView) {
            cachedLocaleCode = parent.strings.localeCode
            let localizedTitles: [String: String] = [
                "name": parent.strings.t("pane.name"),
                "size": parent.strings.t("pane.size"),
                "modified": parent.strings.t("pane.modified"),
                "permissions": parent.strings.t("pane.permissions")
            ]
            for column in tableView.tableColumns {
                if let title = localizedTitles[column.identifier.rawValue] {
                    column.title = title
                }
            }
            tableView.menu = buildContextMenu()
        }

        public func numberOfRows(in _: NSTableView) -> Int {
            cachedFiles.count
        }

        public func tableView(_: NSTableView, rowViewForRow _: Int) -> NSTableRowView? {
            let rowView = ThemedFileRowView()
            let accent = NSColor(hex: parent.palette.accentHex)
            rowView.highlightColor = accent.withAlphaComponent(parent.palette.isDark ? 0.34 : 0.22)
            rowView.hoverColor = accent.withAlphaComponent(parent.palette.isDark ? 0.14 : 0.08)
            return rowView
        }

        public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row >= 0, row < cachedFiles.count, let columnID = tableColumn?.identifier.rawValue else {
                return nil
            }
            let item = cachedFiles[row]
            let cellID = NSUserInterfaceItemIdentifier("Cell-\(columnID)")
            let cell: NSTableCellView = if let reused = tableView.makeView(
                withIdentifier: cellID,
                owner: nil
            ) as? NSTableCellView {
                reused
            } else {
                Self.buildReusableCell(identifier: cellID, includeIcon: columnID == "name")
            }

            let palette = parent.palette
            switch columnID {
            case "name":
                cell.textField?.stringValue = item.name
                cell.textField?.textColor = NSColor(hex: palette.primaryTextHex)
                if item.isDirectory {
                    cell.imageView?.image = Self.folderSymbol
                    cell.imageView?.contentTintColor = NSColor(hex: palette.accentHex)
                } else {
                    cell.imageView?.image = item.isSymlink ? Self.linkSymbol : Self.fileSymbol
                    cell.imageView?.contentTintColor = NSColor(hex: palette.secondaryTextHex)
                }
            case "size":
                let sizeLabel = item.isDirectory
                    ? "--"
                    : Self.byteFormatter.string(fromByteCount: item.size)
                cell.textField?.stringValue = sizeLabel
                cell.textField?.textColor = NSColor(hex: palette.secondaryTextHex)
            case "modified":
                let dateLabel = item.modificationTime.map { Self.dateFormatter.string(from: $0) } ?? "--"
                cell.textField?.stringValue = dateLabel
                cell.textField?.textColor = NSColor(hex: palette.secondaryTextHex)
            case "permissions":
                cell.textField?.stringValue = POSIXPermissions(mode: item.permissions).symbolicString
                cell.textField?.textColor = NSColor(hex: palette.secondaryTextHex)
            default:
                break
            }
            return cell
        }

        public func tableViewSelectionDidChange(_: Notification) {
            guard !isProgrammaticUpdate, let tableView else { return }
            parent.onFocusPane()
            var ids: Set<String> = []
            for row in tableView.selectedRowIndexes where row < cachedFiles.count {
                ids.insert(cachedFiles[row].id)
            }
            lastSyncedSelection = ids
            if parent.selectedIDs != ids {
                parent.selectedIDs = ids
            }
        }

        func syncSelectionToTableView() {
            guard let tableView else { return }
            lastSyncedSelection = parent.selectedIDs
            let matchingIndexes = IndexSet(
                cachedFiles.enumerated().compactMap { parent.selectedIDs.contains($0.element.id) ? $0.offset : nil }
            )
            if tableView.selectedRowIndexes != matchingIndexes {
                tableView.selectRowIndexes(matchingIndexes, byExtendingSelection: false)
            }
        }

        public func tableView(_: NSTableView, didClick tableColumn: NSTableColumn) {
            switch tableColumn.identifier.rawValue {
            case "name": parent.onSortColumn(.name)
            case "size": parent.onSortColumn(.size)
            case "modified": parent.onSortColumn(.modifiedDate)
            case "permissions": parent.onSortColumn(.permissions)
            default: break
            }
        }

        @objc func handleDoubleClick(_ sender: NSTableView) {
            let row = sender.clickedRow
            guard row >= 0, row < cachedFiles.count else { return }
            parent.onActivateRow(cachedFiles[row])
        }

        func activateCurrentSelection() {
            guard let row = tableView?.selectedRow, row >= 0, row < cachedFiles.count else { return }
            parent.onActivateRow(cachedFiles[row])
        }

        func quickLookCurrentSelection() {
            guard let row = tableView?.selectedRow, row >= 0, row < cachedFiles.count else { return }
            parent.onQuickLookRow?(cachedFiles[row])
        }

        func selectRowForContextMenu(_ row: Int) {
            guard row >= 0, row < cachedFiles.count, let tableView else { return }
            parent.onFocusPane()
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }

        func triggerContextAction(_ action: FilePaneContextAction) {
            parent.onFocusPane()
            let selected = tableView?.selectedRow ?? -1
            let target = (selected >= 0 && selected < cachedFiles.count) ? cachedFiles[selected] : nil
            parent.onContextAction(action, target)
        }
    }
}
