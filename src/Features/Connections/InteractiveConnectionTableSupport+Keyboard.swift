import AppKit

extension InteractiveConnectionTableView {
    func isTableResponderFocused() -> Bool {
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
            if event.charactersIgnoringModifiers?.lowercased() == "d" {
                deselectAll(nil)
                return true
            }
        }
        if mods == [.command, .shift], event.charactersIgnoringModifiers?.lowercased() == "a" {
            deselectAll(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if event.keyCode == 53, mods.isEmpty {
            deselectAll(nil)
            return
        }
        if mods == [.command] {
            if event.keyCode == 51 {
                onDeletePressed?()
                return
            }
            if event.charactersIgnoringModifiers?.lowercased() == "a" {
                onSelectAllPressed?()
                return
            }
            if event.charactersIgnoringModifiers?.lowercased() == "d" {
                deselectAll(nil)
                return
            }
        }
        if mods == [.command, .shift], event.charactersIgnoringModifiers?.lowercased() == "a" {
            deselectAll(nil)
            return
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
