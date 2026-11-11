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
}

private struct TableColumnSpec {
    let identifier: String
    let title: String
    let width: CGFloat
}

/// High-performance AppKit NSTableView wrapped for SwiftUI with strict cell dequeue reuse (MEM-004).
public struct FilePaneTableView: NSViewRepresentable {
    public let files: [RemoteFile]
    @Binding public var selectedIDs: Set<String>
    public let isLocalPane: Bool
    public let strings: AppStrings
    public let onActivateRow: (RemoteFile) -> Void
    public let onSortColumn: (FileSortField) -> Void
    public let onFocusPane: () -> Void
    public let onContextAction: (FilePaneContextAction, RemoteFile?) -> Void

    public init(
        files: [RemoteFile],
        selectedIDs: Binding<Set<String>>,
        isLocalPane: Bool = true,
        strings: AppStrings = AppStrings(),
        onActivateRow: @escaping (RemoteFile) -> Void,
        onSortColumn: @escaping (FileSortField) -> Void,
        onFocusPane: @escaping () -> Void,
        onContextAction: @escaping (FilePaneContextAction, RemoteFile?) -> Void = { _, _ in }
    ) {
        self.files = files
        _selectedIDs = selectedIDs
        self.isLocalPane = isLocalPane
        self.strings = strings
        self.onActivateRow = onActivateRow
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

        let tableView = NSTableView()
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = true
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.rowHeight = 22
        tableView.target = context.coordinator
        tableView.doubleAction = #selector(Coordinator.handleDoubleClick(_:))
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator

        let columns: [TableColumnSpec] = [
            TableColumnSpec(identifier: "name", title: strings.t("pane.name"), width: 240),
            TableColumnSpec(identifier: "size", title: strings.t("pane.size"), width: 80),
            TableColumnSpec(identifier: "modified", title: strings.t("pane.modified"), width: 140),
            TableColumnSpec(identifier: "permissions", title: strings.t("pane.permissions"), width: 90)
        ]
        for spec in columns {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(spec.identifier))
            column.title = spec.title
            column.width = spec.width
            column.minWidth = 60
            tableView.addTableColumn(column)
        }

        scrollView.documentView = tableView
        tableView.menu = context.coordinator.buildContextMenu()
        context.coordinator.cachedLocaleCode = strings.localeCode
        context.coordinator.tableView = tableView
        return scrollView
    }

    public func updateNSView(_: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tableView = context.coordinator.tableView else { return }
        if context.coordinator.cachedLocaleCode != strings.localeCode {
            context.coordinator.cachedLocaleCode = strings.localeCode
            let localizedTitles: [String: String] = [
                "name": strings.t("pane.name"),
                "size": strings.t("pane.size"),
                "modified": strings.t("pane.modified"),
                "permissions": strings.t("pane.permissions")
            ]
            for column in tableView.tableColumns {
                if let title = localizedTitles[column.identifier.rawValue] {
                    column.title = title
                }
            }
            tableView.menu = context.coordinator.buildContextMenu()
        }
        if context.coordinator.cachedFiles != files {
            context.coordinator.cachedFiles = files
            context.coordinator.isProgrammaticUpdate = true
            tableView.reloadData()
            let matchingIndexes = IndexSet(
                files.enumerated().compactMap { selectedIDs.contains($0.element.id) ? $0.offset : nil }
            )
            tableView.selectRowIndexes(matchingIndexes, byExtendingSelection: false)
            context.coordinator.isProgrammaticUpdate = false
        }
    }

    @MainActor
    public final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: FilePaneTableView
        var cachedFiles: [RemoteFile] = []
        var cachedLocaleCode: String = ""
        weak var tableView: NSTableView?
        var isProgrammaticUpdate = false

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
        }

        public func numberOfRows(in _: NSTableView) -> Int {
            cachedFiles.count
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

            switch columnID {
            case "name":
                cell.textField?.stringValue = item.name
                let symbolName = item.isDirectory ? "folder.fill" : (item.isSymlink ? "link" : "doc")
                cell.imageView?.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: item.name)
            case "size":
                let sizeLabel = item.isDirectory
                    ? "--"
                    : Self.byteFormatter.string(fromByteCount: item.size)
                cell.textField?.stringValue = sizeLabel
            case "modified":
                let dateLabel = item.modificationTime.map { Self.dateFormatter.string(from: $0) } ?? "--"
                cell.textField?.stringValue = dateLabel
            case "permissions":
                cell.textField?.stringValue = POSIXPermissions(mode: item.permissions).symbolicString
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
            if parent.selectedIDs != ids {
                parent.selectedIDs = ids
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

        func buildContextMenu() -> NSMenu {
            let menu = NSMenu(title: "Commander Actions")
            let specs: [(String, FilePaneContextAction)] = [
                (parent.strings.t("common.open"), .open),
                (parent.isLocalPane ? parent.strings.upload : parent.strings.download, .transfer),
                (parent.strings.t("nav.quickLook"), .quickLook),
                (parent.strings.t("pane.openInNotepad"), .edit),
                (parent.strings.t("common.rename"), .rename),
                (parent.strings.t("pane.chmod"), .permissions),
                (parent.strings.t("pane.getInfo"), .inspect),
                (parent.strings.newFolder, .newFolder),
                (parent.strings.t("common.delete"), .delete)
            ]
            for (title, action) in specs {
                if action == .permissions, parent.isLocalPane {
                    continue
                }
                let item = NSMenuItem(title: title, action: #selector(handleContextMenuClick(_:)), keyEquivalent: "")
                item.target = self
                item.tag = action.rawValue
                menu.addItem(item)
            }
            return menu
        }

        @objc func handleContextMenuClick(_ sender: NSMenuItem) {
            guard let action = FilePaneContextAction(rawValue: sender.tag) else { return }
            parent.onFocusPane()
            let clickedRow = tableView?.clickedRow ?? -1
            let selectedRow = tableView?.selectedRow ?? -1
            let targetIndex = clickedRow >= 0 ? clickedRow : selectedRow
            let targetFile = (targetIndex >= 0 && targetIndex < cachedFiles.count) ? cachedFiles[targetIndex] : nil
            parent.onContextAction(action, targetFile)
        }

        private static func buildReusableCell(
            identifier: NSUserInterfaceItemIdentifier,
            includeIcon: Bool
        ) -> NSTableCellView {
            let cell = NSTableCellView()
            cell.identifier = identifier

            let textField = NSTextField(labelWithString: "")
            textField.lineBreakMode = .byTruncatingMiddle
            textField.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(textField)
            cell.textField = textField

            if includeIcon {
                let imageView = NSImageView()
                imageView.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(imageView)
                cell.imageView = imageView
                NSLayoutConstraint.activate([
                    imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                    imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    imageView.widthAnchor.constraint(equalToConstant: 16),
                    imageView.heightAnchor.constraint(equalToConstant: 16),
                    textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
                    textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                    textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
                ])
            } else {
                NSLayoutConstraint.activate([
                    textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                    textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                    textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
                ])
            }
            return cell
        }
    }
}
