import AppKit
import Foundation
import SparkleCore

public enum DocumentCloseDecision: Sendable {
    case save
    case discard
    case cancel
}

extension EditorSessionManager {
    public func findMatch(forward: Bool) -> Int {
        guard let doc = activeDocument else { return 0 }
        let ranges = findQuery.matchRanges(in: doc.content)
        guard !ranges.isEmpty else { return 0 }

        let currentUTF16 = utf16Offset(in: doc.content, cursor: doc.cursor)
        let selectedRange: NSRange = if forward {
            ranges.first { $0.location > currentUTF16 } ?? ranges[0]
        } else {
            ranges.last { $0.location < currentUTF16 } ?? ranges[ranges.count - 1]
        }
        textViewProxy.selectAndReveal(range: selectedRange)
        return ranges.count
    }

    public func replaceCurrentMatch() {
        guard let doc = activeDocument, !doc.isReadOnly else { return }
        let ranges = findQuery.matchRanges(in: doc.content)
        guard !ranges.isEmpty else { return }
        let currentUTF16 = utf16Offset(in: doc.content, cursor: doc.cursor)
        let target = ranges.first { $0.location >= currentUTF16 } ?? ranges[0]
        let mutable = NSMutableString(string: doc.content)
        mutable.replaceCharacters(in: target, with: findQuery.replaceText)
        let nextOffset = target.location + (findQuery.replaceText as NSString).length
        updateActiveDocument { edited in
            edited.content = mutable as String
            edited.cursor = EditorCursorLocation.locate(in: edited.content, utf16Offset: nextOffset)
            edited.syncStatusKey = "editor.statusModified"
        }
    }

    public func replaceAllMatches() -> Int {
        guard let doc = activeDocument, !doc.isReadOnly else { return 0 }
        let ranges = findQuery.matchRanges(in: doc.content)
        guard !ranges.isEmpty else { return 0 }
        let mutable = NSMutableString(string: doc.content)
        for range in ranges.reversed() {
            mutable.replaceCharacters(in: range, with: findQuery.replaceText)
        }
        updateActiveDocument { edited in
            edited.content = mutable as String
            edited.syncStatusKey = "editor.statusModified"
        }
        return ranges.count
    }

    public func markAllMatches() -> Int {
        guard let doc = activeDocument else { return 0 }
        let ranges = findQuery.matchRanges(in: doc.content)
        findQuery.markedRanges = ranges
        return ranges.count
    }

    public func clearAllMarks() {
        findQuery.markedRanges.removeAll()
        findQuery.bookmarkedLines.removeAll()
    }

    public func copyMarkedText() -> Int {
        guard let doc = activeDocument else { return 0 }
        let nsText = doc.content as NSString
        let extracted = findQuery.markedRanges.compactMap { range -> String? in
            guard range.location + range.length <= nsText.length else { return nil }
            return nsText.substring(with: range)
        }
        guard !extracted.isEmpty else { return 0 }
        let joined = extracted.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(joined, forType: .string)
        return extracted.count
    }

    public func bookmarkMatchingLines() -> Int {
        guard let doc = activeDocument else { return 0 }
        let ranges = findQuery.matchRanges(in: doc.content)
        guard !ranges.isEmpty else { return 0 }
        var lineNumbers = Set<Int>()
        for range in ranges {
            let loc = EditorCursorLocation.locate(in: doc.content, utf16Offset: range.location)
            lineNumbers.insert(loc.line)
        }
        findQuery.bookmarkedLines = lineNumbers
        return lineNumbers.count
    }

    public func promptSaveBeforeClosing(document doc: EditorDocument) -> DocumentCloseDecision {
        guard doc.content != doc.savedContent else { return .discard }
        let alert = NSAlert()
        alert.messageText = "Do you want to save the changes made to \"\(doc.title)\"?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            return .save
        case .alertSecondButtonReturn:
            return .discard
        default:
            return .cancel
        }
    }

    @discardableResult
    public func closeDocumentWithPrompt(
        id: UUID,
        saveAction: ((EditorDocument) async -> Void)? = nil
    ) async -> Bool {
        guard let doc = documents.first(where: { $0.id == id }) else { return true }
        if doc.isDirty {
            activeDocumentID = id
            let decision = promptSaveBeforeClosing(document: doc)
            switch decision {
            case .save:
                if let saveAction {
                    await saveAction(doc)
                }
                closeDocument(id: id)
                return true
            case .discard:
                closeDocument(id: id)
                return true
            case .cancel:
                return false
            }
        }
        closeDocument(id: id)
        return true
    }

    func utf16Offset(in text: String, cursor: EditorCursorLocation) -> Int {
        var line = 1
        var col = 1
        var utf16Count = 0
        for char in text {
            if line > cursor.line || (line == cursor.line && col >= cursor.column) {
                break
            }
            if char == "\n" {
                line += 1
                col = 1
            } else {
                col += 1
            }
            utf16Count += String(char).utf16.count
        }
        return utf16Count
    }
}
