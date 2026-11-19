import AppKit
import SparkleCore
import SparkleDesignSystem
import SparkleFileManager
import SwiftUI

public extension FilePaneTableView {
    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
        var parent: FilePaneTableView
        var cachedFiles: [RemoteFile] = []
        var cachedPalette: SparkleThemePalette?
        var cachedLocaleCode: String = ""
        var lastSyncedSelection: Set<String> = []
        weak var scrollView: NSScrollView?
        weak var tableView: NSTableView?
        var isProgrammaticUpdate = false
        var isMenuOpen = false
        var deferredReload = false
        private var focusObserver: NSObjectProtocol?

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

        func removeFocusObserver() {
            if let focusObserver {
                NotificationCenter.default.removeObserver(focusObserver)
                self.focusObserver = nil
            }
        }

        func installFocusObserver() {
            guard focusObserver == nil else { return }
            focusObserver = NotificationCenter.default.addObserver(
                forName: .sparklePaneFocusRequested,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let targetLocal = notification.userInfo?["isLocal"] as? Bool else { return }
                let targetWindow = notification.object as? NSWindow
                Task { @MainActor [weak self] in
                    guard let coordinator = self,
                          let tableView = coordinator.tableView,
                          let window = tableView.window,
                          targetWindow == nil || window === targetWindow,
                          targetLocal == coordinator.parent.isLocalPane
                    else { return }
                    window.makeFirstResponder(tableView)
                    coordinator.parent.onFocusPane()
                }
            }
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

        func applyFilesUpdate(files: [RemoteFile], tableView: NSTableView, themeChanged: Bool) {
            let oldFiles = cachedFiles
            cachedFiles = files
            deferredReload = false
            if themeChanged || oldFiles.isEmpty || files.isEmpty {
                tableView.reloadData()
                return
            }
            let oldParent = oldFiles.first?.path.parent
            let newParent = files.first?.path.parent
            if oldParent != newParent || abs(oldFiles.count - files.count) > 15 || files.count > 100 {
                tableView.reloadData()
                return
            }
            let diff = files.difference(from: oldFiles)
            if diff.count <= 30 {
                var removals = IndexSet()
                var insertions = IndexSet()
                for change in diff {
                    switch change {
                    case let .remove(offset, _, _):
                        removals.insert(offset)
                    case let .insert(offset, _, _):
                        insertions.insert(offset)
                    }
                }
                tableView.beginUpdates()
                if !removals.isEmpty {
                    tableView.removeRows(at: removals, withAnimation: .effectFade)
                }
                if !insertions.isEmpty {
                    tableView.insertRows(at: insertions, withAnimation: .effectFade)
                }
                tableView.endUpdates()
            } else {
                tableView.reloadData()
            }
        }

        func handleDroppedURLs(_ urls: [URL]) {
            if parent.isLocalPane {
                if let firstDir = urls.first(where: {
                    (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                }) {
                    let navDir = RemoteFile(
                        name: firstDir.lastPathComponent,
                        path: RemotePath(rawValue: firstDir.path),
                        size: 0,
                        isDirectory: true
                    )
                    parent.onActivateRow(navDir)
                }
            } else {
                parent.onContextAction(.transfer, nil)
                NotificationCenter.default.post(
                    name: .sparkleUploadDroppedFiles,
                    object: nil,
                    userInfo: ["urls": urls]
                )
            }
        }

        public func tableView(_: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
            guard row >= 0, row < cachedFiles.count else { return nil }
            let file = cachedFiles[row]
            if parent.isLocalPane {
                return URL(fileURLWithPath: file.path.rawValue) as NSURL
            }
            return nil
        }

        public func numberOfRows(in _: NSTableView) -> Int {
            cachedFiles.count
        }

        public func tableView(_ tableView: NSTableView, rowViewForRow _: Int) -> NSTableRowView? {
            let rowID = NSUserInterfaceItemIdentifier("ThemedFileRowView")
            let rowView: ThemedFileRowView
            if let reused = tableView.makeView(withIdentifier: rowID, owner: nil) as? ThemedFileRowView {
                rowView = reused
            } else {
                let newRow = ThemedFileRowView()
                newRow.identifier = rowID
                rowView = newRow
            }
            let accent = NSColor(hex: parent.palette.accentHex)
            rowView.accentIndicatorColor = accent
            rowView.highlightColor = accent.withAlphaComponent(parent.palette.isDark ? 0.38 : 0.26)
            rowView.hoverColor = accent.withAlphaComponent(parent.palette.isDark ? 0.16 : 0.10)
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

        public func selectionShouldChange(in tableView: NSTableView) -> Bool {
            guard let interactive = tableView as? InteractiveFileTableView else { return true }
            return !interactive.isScrollingActive
        }

        public func tableView(_ tableView: NSTableView, shouldSelectRow _: Int) -> Bool {
            guard let interactive = tableView as? InteractiveFileTableView else { return true }
            return !interactive.isScrollingActive
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
            didClickColumn(tableColumn)
        }
    }
}
