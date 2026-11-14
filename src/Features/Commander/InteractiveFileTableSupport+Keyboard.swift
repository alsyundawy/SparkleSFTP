import AppKit
import SparkleDesignSystem

// MARK: - Keyboard & Shortcut Handling

extension InteractiveFileTableView {
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
        case 53 where mods.isEmpty:
            onContextActionShortcut?(.deselectAll)
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
        if mods == [.command, .shift] {
            if event.charactersIgnoringModifiers?.lowercased() == "a" {
                onContextActionShortcut?(.deselectAll)
                return true
            }
            if event.charactersIgnoringModifiers?.lowercased() == "c" {
                onContextActionShortcut?(.copyFileNames)
                return true
            }
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
        if handleCommandKeyCodeShortcut(event.keyCode) {
            return true
        }
        guard let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
        return handleCommandCharacterShortcut(key)
    }

    private func handleCommandKeyCodeShortcut(_ keyCode: UInt16) -> Bool {
        switch keyCode {
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
            return false
        }
    }

    private func handleCommandCharacterShortcut(_ key: String) -> Bool {
        switch key {
        case "a":
            onContextActionShortcut?(.selectAll)
            return true
        case "d":
            onContextActionShortcut?(.deselectAll)
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
        if mods == [.shift], event.keyCode == 96 {
            onContextActionShortcut?(.copyTo)
            return true
        }
        guard mods.isEmpty else { return false }
        let action: FilePaneContextAction? = switch event.keyCode {
        case 120: .rename
        case 96: .transfer
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
