import AppKit
import SparkleCore

enum ConnectionTableRowItem: Equatable {
    case section(id: String, title: String, groupID: UUID?)
    case profile(ConnectionProfile, rowKey: String)
}

final class InteractiveConnectionTableView: NSTableView {
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

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(selectAll(_:)):
            numberOfRows > 0
        case #selector(delete(_:)):
            !selectedRowIndexes.isEmpty
        default:
            super.validateUserInterfaceItem(item)
        }
    }

    override func selectAll(_: Any?) {
        onSelectAllPressed?()
    }

    @objc func delete(_: Any?) {
        onDeletePressed?()
    }

    private func isTableResponderFocused() -> Bool {
        guard let responder = window?.firstResponder else { return false }
        if responder is NSText {
            return false
        }
        if responder === self {
            return true
        }
        if let responderView = responder as? NSView {
            return responderView.isDescendant(of: self)
        }
        return false
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isTableResponderFocused() else {
            return super.performKeyEquivalent(with: event)
        }
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if mods == [.command] {
            if event.keyCode == 51 {
                onDeletePressed?()
                return true
            }
            if event.charactersIgnoringModifiers?.lowercased() == "a" {
                onSelectAllPressed?()
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if mods == [.command] {
            if event.keyCode == 51 {
                onDeletePressed?()
                return
            }
            if event.charactersIgnoringModifiers?.lowercased() == "a" {
                onSelectAllPressed?()
                return
            }
        }
        switch event.keyCode {
        case 36 where mods.isEmpty, 76 where mods.isEmpty:
            onReturnPressed?()
        case 51 where mods.isEmpty, 117 where mods.isEmpty:
            onDeletePressed?()
        default:
            super.keyDown(with: event)
        }
    }
}
