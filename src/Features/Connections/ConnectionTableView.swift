import AppKit
import SparkleCore
import SparkleDesignSystem
import SwiftUI

enum ConnectionTableRowItem: Equatable {
    case section(id: String, title: String, groupID: UUID?)
    case profile(ConnectionProfile, rowKey: String)
}

private final class InteractiveConnectionTableView: NSTableView {
    var onReturnPressed: (() -> Void)?
    var onDeletePressed: (() -> Void)?
    var onSelectAllPressed: (() -> Void)?
    var onRightClickSelectRow: ((Int) -> Void)?

    override var acceptsFirstResponder: Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let localPoint = convert(event.locationInWindow, from: nil)
        let hitRow = row(at: localPoint)
        if hitRow >= 0, !isRowSelected(hitRow) {
            onRightClickSelectRow?(hitRow)
        }
        super.rightMouseDown(with: event)
    }

    override func selectAll(_: Any?) {
        onSelectAllPressed?()
    }

    @objc func delete(_: Any?) {
        onDeletePressed?()
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "a" {
            onSelectAllPressed?()
            return
        }
        switch event.keyCode {
        case 36, 76:
            onReturnPressed?()
        case 51, 117:
            onDeletePressed?()
        default:
            super.keyDown(with: event)
        }
    }
}

private final class ThemedConnectionRowView: NSTableRowView {
    var highlightColor = NSColor.selectedContentBackgroundColor
    var hoverColor = NSColor.labelColor.withAlphaComponent(0.08)
    private var hoverTrackingArea: NSTrackingArea?
    private var isHovered = false {
        didSet {
            if oldValue != isHovered {
                needsDisplay = true
            }
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        isHovered = false
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        super.mouseEntered(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        super.mouseExited(with: event)
    }

    override func drawBackground(in dirtyRect: NSRect) {
        super.drawBackground(in: dirtyRect)
        guard !isSelected, isHovered, !isGroupRowStyle else { return }
        hoverColor.setFill()
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 1), xRadius: 5, yRadius: 5)
        path.fill()
    }

    override func drawSelection(in _: NSRect) {
        guard selectionHighlightStyle != .none, isSelected else { return }
        highlightColor.setFill()
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 1), xRadius: 5, yRadius: 5)
        path.fill()
    }
}

struct ConnectionListTableView: NSViewRepresentable {
    let rows: [ConnectionTableRowItem]
    @Binding var selectedIDs: Set<UUID>
    let strings: AppStrings
    let palette: SparkleThemePalette
    let onConnect: (ConnectionProfile) -> Void
    let onConnectInNewTab: (ConnectionProfile) -> Void
    let onConnectInNewWindow: (ConnectionProfile) -> Void
    let onOpenExternalTerminal: (ConnectionProfile) -> Void
    let onNewConnection: () -> Void
    let onNewGroup: () -> Void
    let onSelectAll: () -> Void
    let onEdit: (ConnectionProfile) -> Void
    let onClone: (ConnectionProfile) -> Void
    let onRequestDelete: (Set<UUID>) -> Void
    let onDeleteGroup: (UUID) -> Void

    func makeCoordinator() -> ConnectionListCoordinator {
        ConnectionListCoordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true

        let tableView = InteractiveConnectionTableView()
        tableView.headerView = nil
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.allowsMultipleSelection = true
        tableView.allowsEmptySelection = true
        tableView.allowsTypeSelect = true
        tableView.rowHeight = 36
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.target = context.coordinator
        tableView.doubleAction = #selector(ConnectionListCoordinator.handleDoubleClick(_:))
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.onReturnPressed = { [weak coordinator = context.coordinator] in
            coordinator?.activateSelectedProfile()
        }
        tableView.onDeletePressed = { [weak coordinator = context.coordinator] in
            coordinator?.requestDeleteSelected()
        }
        tableView.onSelectAllPressed = { [weak coordinator = context.coordinator] in
            coordinator?.selectAllProfiles()
        }
        tableView.onRightClickSelectRow = { [weak coordinator = context.coordinator] row in
            coordinator?.selectProfileRowIfEligible(row)
        }

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("connection"))
        col.resizingMask = .autoresizingMask
        tableView.addTableColumn(col)

        scrollView.documentView = tableView
        context.coordinator.scrollView = scrollView
        context.coordinator.tableView = tableView
        context.coordinator.applyTheme(palette)
        tableView.menu = context.coordinator.buildMenu()
        return scrollView
    }

    func updateNSView(_: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tableView = context.coordinator.tableView else { return }

        let themeChanged = context.coordinator.cachedPalette != palette
        if themeChanged {
            context.coordinator.applyTheme(palette)
        }
        if context.coordinator.cachedLocaleCode != strings.localeCode {
            context.coordinator.cachedLocaleCode = strings.localeCode
            tableView.menu = context.coordinator.buildMenu()
        }
        let rowsChanged = context.coordinator.cachedRows != rows
        if rowsChanged || themeChanged {
            context.coordinator.cachedRows = rows
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

@MainActor
final class ConnectionListCoordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    var parent: ConnectionListTableView
    var cachedRows: [ConnectionTableRowItem] = []
    var cachedPalette: SparkleThemePalette?
    var cachedLocaleCode = ""
    var lastSyncedSelection: Set<UUID> = []
    var isProgrammaticUpdate = false
    weak var scrollView: NSScrollView?
    weak var tableView: NSTableView?

    private static let secureSymbol = NSImage(
        systemSymbolName: SparkleTheme.Symbols.sftp,
        accessibilityDescription: nil
    )
    private static let insecureSymbol = NSImage(
        systemSymbolName: SparkleTheme.Symbols.ftpInsecure,
        accessibilityDescription: nil
    )

    static func symbolImage(isEncrypted: Bool) -> NSImage? {
        isEncrypted ? secureSymbol : insecureSymbol
    }

    init(parent: ConnectionListTableView) {
        self.parent = parent
        cachedRows = parent.rows
        lastSyncedSelection = parent.selectedIDs
    }

    func applyTheme(_ palette: SparkleThemePalette) {
        cachedPalette = palette
        let windowColor = NSColor(hex: palette.windowHex)
        scrollView?.backgroundColor = windowColor
        tableView?.backgroundColor = windowColor
    }

    func numberOfRows(in _: NSTableView) -> Int {
        cachedRows.count
    }

    func tableView(_: NSTableView, isGroupRow row: Int) -> Bool {
        guard row >= 0, row < cachedRows.count else { return false }
        if case .section = cachedRows[row] {
            return true
        }
        return false
    }

    func tableView(_: NSTableView, shouldSelectRow row: Int) -> Bool {
        guard row >= 0, row < cachedRows.count else { return false }
        if case .profile = cachedRows[row] {
            return true
        }
        return false
    }

    func tableView(_: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard row >= 0, row < cachedRows.count else { return 36 }
        if case .section = cachedRows[row] {
            return 24
        }
        return 38
    }

    func tableView(_: NSTableView, rowViewForRow _: Int) -> NSTableRowView? {
        let rowView = ThemedConnectionRowView()
        let accent = NSColor(hex: parent.palette.accentHex)
        rowView.highlightColor = accent.withAlphaComponent(parent.palette.isDark ? 0.34 : 0.22)
        rowView.hoverColor = accent.withAlphaComponent(parent.palette.isDark ? 0.14 : 0.10)
        return rowView
    }

    func tableView(_ tableView: NSTableView, viewFor _: NSTableColumn?, row: Int) -> NSView? {
        guard row >= 0, row < cachedRows.count else { return nil }
        switch cachedRows[row] {
        case let .section(_, title, _):
            let id = NSUserInterfaceItemIdentifier("ConnHeaderCell")
            let field = (tableView.makeView(withIdentifier: id, owner: nil) as? NSTextField)
                ?? makeHeaderLabel(identifier: id)
            field.stringValue = title.uppercased()
            field.textColor = NSColor(hex: parent.palette.secondaryTextHex)
            return field

        case let .profile(profile, _):
            let id = NSUserInterfaceItemIdentifier("ConnProfileCell")
            let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView)
                ?? makeProfileCell(identifier: id)
            configureProfileCell(cell, profile: profile)
            return cell
        }
    }

    func tableViewSelectionDidChange(_: Notification) {
        guard !isProgrammaticUpdate, let tableView else { return }
        var ids: Set<UUID> = []
        for idx in tableView.selectedRowIndexes where idx < cachedRows.count {
            if case let .profile(profile, _) = cachedRows[idx] {
                ids.insert(profile.id)
            }
        }
        lastSyncedSelection = ids
        if parent.selectedIDs != ids {
            parent.selectedIDs = ids
        }
    }

    func syncSelectionToTableView() {
        guard let tableView else { return }
        let selected = parent.selectedIDs
        lastSyncedSelection = selected
        var matching = IndexSet()
        for (idx, item) in cachedRows.enumerated() {
            if case let .profile(profile, _) = item, selected.contains(profile.id) {
                matching.insert(idx)
            }
        }
        if tableView.selectedRowIndexes != matching {
            tableView.selectRowIndexes(matching, byExtendingSelection: false)
        }
    }

    @objc func handleDoubleClick(_ sender: NSTableView) {
        let row = sender.clickedRow >= 0 ? sender.clickedRow : sender.selectedRow
        guard row >= 0, row < cachedRows.count else { return }
        if case let .profile(profile, _) = cachedRows[row] {
            parent.onConnect(profile)
        }
    }

    func activateSelectedProfile() {
        guard let row = tableView?.selectedRow, row >= 0, row < cachedRows.count else { return }
        if case let .profile(profile, _) = cachedRows[row] {
            parent.onConnect(profile)
        }
    }

    func requestDeleteSelected() {
        guard !parent.selectedIDs.isEmpty else { return }
        parent.onRequestDelete(parent.selectedIDs)
    }

    func selectAllProfiles() {
        parent.onSelectAll()
    }

    func selectProfileRowIfEligible(_ row: Int) {
        guard row >= 0, row < cachedRows.count,
              case .profile = cachedRows[row],
              let tableView
        else { return }
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    }
}
