import AppKit
import SparkleCore
import SparkleFileManager
import SwiftUI

private struct TableColumnSpec {
    let identifier: String
    let title: String
    let width: CGFloat
}

/// High-performance AppKit NSTableView wrapped for SwiftUI with strict cell dequeue reuse (MEM-004).
public struct FilePaneTableView: NSViewRepresentable {
    public let files: [RemoteFile]
    @Binding public var selectedIDs: Set<String>
    public let onActivateRow: (RemoteFile) -> Void
    public let onSortColumn: (FileSortField) -> Void
    public let onFocusPane: () -> Void

    public init(
        files: [RemoteFile],
        selectedIDs: Binding<Set<String>>,
        onActivateRow: @escaping (RemoteFile) -> Void,
        onSortColumn: @escaping (FileSortField) -> Void,
        onFocusPane: @escaping () -> Void
    ) {
        self.files = files
        self._selectedIDs = selectedIDs
        self.onActivateRow = onActivateRow
        self.onSortColumn = onSortColumn
        self.onFocusPane = onFocusPane
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
            TableColumnSpec(identifier: "name", title: "Name", width: 240),
            TableColumnSpec(identifier: "size", title: "Size", width: 80),
            TableColumnSpec(identifier: "modified", title: "Modified", width: 140),
            TableColumnSpec(identifier: "permissions", title: "Permissions", width: 90)
        ]
        for spec in columns {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(spec.identifier))
            column.title = spec.title
            column.width = spec.width
            column.minWidth = 60
            tableView.addTableColumn(column)
        }

        scrollView.documentView = tableView
        context.coordinator.tableView = tableView
        return scrollView
    }

    public func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tableView = context.coordinator.tableView else { return }
        if context.coordinator.cachedFiles != files {
            context.coordinator.cachedFiles = files
            tableView.reloadData()
        }
    }

    @MainActor
    public final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: FilePaneTableView
        var cachedFiles: [RemoteFile] = []
        weak var tableView: NSTableView?

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
            self.cachedFiles = parent.files
        }

        public func numberOfRows(in tableView: NSTableView) -> Int {
            cachedFiles.count
        }

        public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row >= 0, row < cachedFiles.count, let columnID = tableColumn?.identifier.rawValue else {
                return nil
            }
            let item = cachedFiles[row]
            let cellID = NSUserInterfaceItemIdentifier("Cell-\(columnID)")
            let cell: NSTableCellView
            if let reused = tableView.makeView(withIdentifier: cellID, owner: nil) as? NSTableCellView {
                cell = reused
            } else {
                cell = Self.buildReusableCell(identifier: cellID, includeIcon: columnID == "name")
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

        public func tableViewSelectionDidChange(_ notification: Notification) {
            guard let tableView else { return }
            parent.onFocusPane()
            var ids: Set<String> = []
            for row in tableView.selectedRowIndexes where row < cachedFiles.count {
                ids.insert(cachedFiles[row].id)
            }
            parent.selectedIDs = ids
        }

        public func tableView(_ tableView: NSTableView, didClick tableColumn: NSTableColumn) {
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
