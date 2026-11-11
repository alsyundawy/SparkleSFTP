import AppKit
import SparkleDesignSystem
import SwiftUI

/// Action proxy allowing toolbar buttons to drive native AppKit `NSTextView` commands reliably.
@MainActor
public final class NotepadTextViewProxy {
    public weak var textView: NSTextView?

    public init() {}

    public func undo() {
        textView?.undoManager?.undo()
    }

    public func redo() {
        textView?.undoManager?.redo()
    }

    public func cut() {
        textView?.cut(nil)
    }

    public func copySelection() {
        textView?.copy(nil)
    }

    public func paste() {
        textView?.paste(nil)
    }

    public func selectAndReveal(range: NSRange) {
        guard let textView, range.location != NSNotFound else { return }
        let safeMax = (textView.string as NSString).length
        let clampedLoc = min(max(0, range.location), safeMax)
        let clampedLen = min(max(0, range.length), max(0, safeMax - clampedLoc))
        let safeRange = NSRange(location: clampedLoc, length: clampedLen)
        textView.setSelectedRange(safeRange)
        textView.scrollRangeToVisible(safeRange)
        textView.showFindIndicator(for: safeRange)
        textView.window?.makeFirstResponder(textView)
    }

    public func goToLine(_ oneBasedLine: Int) {
        guard let textView else { return }
        let text = textView.string as NSString
        let target = max(1, oneBasedLine)
        var currentLine = 1
        var offset = 0
        while currentLine < target, offset < text.length {
            let lineRange = text.lineRange(for: NSRange(location: offset, length: 0))
            let nextOffset = NSMaxRange(lineRange)
            if nextOffset <= offset {
                break
            }
            offset = nextOffset
            currentLine += 1
        }
        selectAndReveal(range: NSRange(location: offset, length: 0))
    }
}

/// AppKit `NSTextView` wrapper with line numbers, whitespace glyphs, zoom, syntax highlight, and read-only lock.
public struct NotepadTextView: NSViewRepresentable {
    @Binding public var content: String
    @Binding public var cursor: EditorCursorLocation
    @Binding public var selectionLength: Int
    public let documentID: UUID
    public let syntax: EditorSyntaxLanguage
    public let palette: SparkleThemePalette
    public let fontSize: CGFloat
    public let wordWrap: Bool
    public let showLineNumbers: Bool
    public let showWhitespace: Bool
    public let isReadOnly: Bool
    public let proxy: NotepadTextViewProxy

    public init(
        content: Binding<String>,
        cursor: Binding<EditorCursorLocation>,
        selectionLength: Binding<Int>,
        documentID: UUID,
        syntax: EditorSyntaxLanguage,
        palette: SparkleThemePalette,
        fontSize: CGFloat,
        wordWrap: Bool,
        showLineNumbers: Bool,
        showWhitespace: Bool,
        isReadOnly: Bool,
        proxy: NotepadTextViewProxy
    ) {
        _content = content
        _cursor = cursor
        _selectionLength = selectionLength
        self.documentID = documentID
        self.syntax = syntax
        self.palette = palette
        self.fontSize = fontSize
        self.wordWrap = wordWrap
        self.showLineNumbers = showLineNumbers
        self.showWhitespace = showWhitespace
        self.isReadOnly = isReadOnly
        self.proxy = proxy
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = NSTextView()
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.textContainerInset = NSSize(width: 8, height: 10)
        textView.autoresizingMask = [.width]
        textView.delegate = context.coordinator

        scrollView.documentView = textView
        let ruler = NotepadLineNumberRulerView(scrollView: scrollView, textView: textView)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = showLineNumbers

        context.coordinator.scrollView = scrollView
        context.coordinator.textView = textView
        context.coordinator.rulerView = ruler
        proxy.textView = textView

        applyConfiguration(to: textView, scrollView: scrollView, coordinator: context.coordinator, forceHighlight: true)
        return scrollView
    }

    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        proxy.textView = context.coordinator.textView
        guard let textView = context.coordinator.textView else { return }
        applyConfiguration(
            to: textView,
            scrollView: scrollView,
            coordinator: context.coordinator,
            forceHighlight: false
        )
    }

    private func applyConfiguration(
        to textView: NSTextView,
        scrollView: NSScrollView,
        coordinator: Coordinator,
        forceHighlight: Bool
    ) {
        let switchedDocument = coordinator.lastDocumentID != documentID
        var needsHighlight = forceHighlight || switchedDocument

        if switchedDocument || textView.string != content {
            coordinator.isProgrammaticChange = true
            let previousSelection = textView.selectedRange()
            textView.string = content
            if switchedDocument {
                textView.setSelectedRange(NSRange(location: 0, length: 0))
            } else {
                let len = (textView.string as NSString).length
                let loc = min(previousSelection.location, len)
                textView.setSelectedRange(NSRange(location: loc, length: min(previousSelection.length, len - loc)))
            }
            coordinator.lastDocumentID = documentID
            coordinator.isProgrammaticChange = false
            needsHighlight = true
        }

        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        if textView.font != font {
            textView.font = font
            needsHighlight = true
        }
        if coordinator.lastSyntax != syntax || coordinator.lastPalette != palette {
            coordinator.lastSyntax = syntax
            coordinator.lastPalette = palette
            needsHighlight = true
        }

        textView.isEditable = !isReadOnly
        textView.backgroundColor = NSColor(hex: palette.canvasHex)
        textView.insertionPointColor = NSColor(hex: palette.accentHex)
        textView.selectedTextAttributes = [
            .backgroundColor: NSColor(hex: palette.accentHex).withAlphaComponent(0.26),
            .foregroundColor: NSColor(hex: palette.primaryTextHex)
        ]

        configureWordWrap(textView: textView, scrollView: scrollView, wrap: wordWrap)
        textView.layoutManager?.showsInvisibleCharacters = showWhitespace
        scrollView.rulersVisible = showLineNumbers
        coordinator.rulerView?.palette = palette
        coordinator.rulerView?.font = font
        coordinator.rulerView?.needsDisplay = true

        if needsHighlight, let storage = textView.textStorage {
            EditorSyntaxHighlighter.applyHighlighting(
                to: storage,
                language: syntax,
                palette: palette,
                font: font
            )
        }
    }

    private func configureWordWrap(textView: NSTextView, scrollView: NSScrollView, wrap: Bool) {
        guard let container = textView.textContainer else { return }
        if wrap {
            let width = max(240, scrollView.contentSize.width)
            container.widthTracksTextView = true
            container.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
            textView.isHorizontallyResizable = false
            textView.frame.size.width = width
        } else {
            container.widthTracksTextView = false
            container.containerSize = NSSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
            textView.isHorizontallyResizable = true
        }
    }

    @MainActor
    public final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NotepadTextView
        weak var scrollView: NSScrollView?
        weak var textView: NSTextView?
        weak var rulerView: NotepadLineNumberRulerView?
        var isProgrammaticChange = false
        var lastDocumentID: UUID?
        var lastSyntax: EditorSyntaxLanguage?
        var lastPalette: SparkleThemePalette?

        init(parent: NotepadTextView) {
            self.parent = parent
        }

        public func textDidChange(_: Notification) {
            guard !isProgrammaticChange, let textView else { return }
            let updated = textView.string
            if parent.content != updated {
                parent.content = updated
            }
            if let storage = textView.textStorage {
                let font = NSFont.monospacedSystemFont(ofSize: parent.fontSize, weight: .regular)
                EditorSyntaxHighlighter.applyHighlighting(
                    to: storage,
                    language: parent.syntax,
                    palette: parent.palette,
                    font: font
                )
            }
            rulerView?.needsDisplay = true
        }

        public func textViewDidChangeSelection(_: Notification) {
            guard let textView else { return }
            let sel = textView.selectedRange()
            let nextCursor = EditorCursorLocation.locate(in: textView.string, utf16Offset: sel.location)
            if parent.cursor != nextCursor {
                parent.cursor = nextCursor
            }
            if parent.selectionLength != sel.length {
                parent.selectionLength = sel.length
            }
        }
    }
}
