import AppKit
import SparkleDesignSystem

struct FilePaneColumnSpec {
    let identifier: String
    let title: String
    let width: CGFloat
}

final class InteractiveFileTableView: NSTableView {
    var onActivateSelected: (() -> Void)?
    var onQuickLookSelected: (() -> Void)?
    var onGoParent: (() -> Void)?
    var onSwitchPane: (() -> Void)?
    var onRightClickSelectRow: ((Int) -> Void)?
    var onContextActionShortcut: ((FilePaneContextAction) -> Void)?

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
            return numberOfRows > 0
        case #selector(copy(_:)), #selector(delete(_:)):
            return !selectedRowIndexes.isEmpty
        default:
            return super.validateUserInterfaceItem(item)
        }
    }

    override func selectAll(_: Any?) {
        onContextActionShortcut?(.selectAll)
    }

    @objc func copy(_: Any?) {
        onContextActionShortcut?(.copyClipboard)
    }

    @objc func delete(_: Any?) {
        onContextActionShortcut?(.delete)
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
        if handleModifierKey(event) || handleFunctionKey(event) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if handleModifierKey(event) || handleFunctionKey(event) {
            return
        }
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        switch event.keyCode {
        case 48 where mods.isEmpty:
            onSwitchPane?()
        case 36 where mods.isEmpty, 76 where mods.isEmpty:
            onActivateSelected?()
        case 49 where mods.isEmpty:
            onQuickLookSelected?()
        case 51 where mods.isEmpty:
            onGoParent?()
        case 117 where mods.isEmpty:
            onContextActionShortcut?(.delete)
        default:
            super.keyDown(with: event)
        }
    }

    private func handleModifierKey(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if mods == [.command] {
            return handleCommandOnlyShortcut(event)
        }
        if mods == [.command, .shift], event.charactersIgnoringModifiers?.lowercased() == "c" {
            onContextActionShortcut?(.copyFileNames)
            return true
        }
        if mods == [.command, .option], event.charactersIgnoringModifiers?.lowercased() == "c" {
            onContextActionShortcut?(.copyFullPaths)
            return true
        }
        if mods == [.option], event.keyCode == 36 || event.keyCode == 76 {
            onContextActionShortcut?(.inspect)
            return true
        }
        return false
    }

    private func handleCommandOnlyShortcut(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 51:
            onContextActionShortcut?(.delete)
            return true
        case 126:
            onGoParent?()
            return true
        case 125:
            onActivateSelected?()
            return true
        case 36, 76:
            onContextActionShortcut?(.insertCommandLine)
            return true
        default:
            break
        }
        guard let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
        switch key {
        case "a":
            onContextActionShortcut?(.selectAll)
            return true
        case "c":
            onContextActionShortcut?(.copyClipboard)
            return true
        case "i":
            onContextActionShortcut?(.inspect)
            return true
        default:
            return false
        }
    }

    private func handleFunctionKey(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard mods.isEmpty else { return false }
        let action: FilePaneContextAction? = switch event.keyCode {
        case 120: .rename
        case 96: .copyTo
        case 97: .moveTo
        case 98: .newFolder
        case 100: .delete
        case 101: .inspect
        default: nil
        }
        guard let action else { return false }
        onContextActionShortcut?(action)
        return true
    }
}

final class ThemedFileRowView: NSTableRowView {
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
        guard !isSelected, isHovered else { return }
        hoverColor.setFill()
        bounds.fill()
    }

    override func drawSelection(in _: NSRect) {
        guard selectionHighlightStyle != .none, isSelected else { return }
        highlightColor.setFill()
        bounds.fill()
    }
}
