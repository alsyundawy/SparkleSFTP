import AppKit
import SparkleDesignSystem

/// Lightweight AppKit `NSRulerView` painting line numbers aligned with `NSTextView` layout fragments.
final class NotepadLineNumberRulerView: NSRulerView {
    var palette: SparkleThemePalette = SparkleThemeCatalog.defaultLight {
        didSet { needsDisplay = true }
    }

    var font: NSFont = .monospacedSystemFont(ofSize: 13, weight: .regular) {
        didSet { needsDisplay = true }
    }

    init(scrollView: NSScrollView, textView: NSTextView) {
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 44
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTextOrBoundsChanged(_:)),
            name: NSText.didChangeNotification,
            object: textView
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTextOrBoundsChanged(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
    }

    @available(*, unavailable)
    required init(coder _: NSCoder) {
        fatalError("init(coder:) is not implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleTextOrBoundsChanged(_: Notification) {
        needsDisplay = true
    }

    override func drawHashMarksAndLabels(in _: NSRect) {
        guard let textView = clientView as? NSTextView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer
        else { return }

        let gutterBG = NSColor(hex: palette.windowHex)
        let borderCol = NSColor(hex: palette.borderHex)
        let numCol = NSColor(hex: palette.secondaryTextHex)

        gutterBG.setFill()
        bounds.fill()

        borderCol.setFill()
        NSRect(x: bounds.width - 1, y: 0, width: 1, height: bounds.height).fill()

        let visibleRect = scrollView?.contentView.bounds ?? textView.visibleRect
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        let nsText = textView.string as NSString
        var lineNumber = countNewlines(in: nsText, upTo: charRange.location) + 1
        var index = charRange.location
        let maxIndex = min(nsText.length, charRange.location + charRange.length)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: max(10, font.pointSize - 1), weight: .regular),
            .foregroundColor: numCol
        ]

        if nsText.length == 0 {
            drawLabel("1", atY: textView.textContainerOrigin.y, attrs: attrs, scrollOffset: visibleRect.origin.y)
            return
        }

        while index <= maxIndex, index < nsText.length {
            let lineRange = nsText.lineRange(for: NSRange(location: min(index, nsText.length), length: 0))
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: lineRange.location)
            guard glyphIndex < layoutManager.numberOfGlyphs else { break }
            var lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            lineRect.origin.y += textView.textContainerOrigin.y
            drawLabel("\(lineNumber)", atY: lineRect.origin.y + 1, attrs: attrs, scrollOffset: visibleRect.origin.y)

            lineNumber += 1
            let nextIndex = NSMaxRange(lineRange)
            if nextIndex <= index || nextIndex >= nsText.length {
                if nextIndex == nsText.length, nsText.hasSuffix("\n") {
                    drawLabel(
                        "\(lineNumber)",
                        atY: lineRect.maxY + 1,
                        attrs: attrs,
                        scrollOffset: visibleRect.origin.y
                    )
                }
                break
            }
            index = nextIndex
        }
    }

    private func countNewlines(in text: NSString, upTo limit: Int) -> Int {
        guard limit > 0 else { return 0 }
        let safeLimit = min(limit, text.length)
        var count = 0
        for idx in 0 ..< safeLimit where text.character(at: idx) == 10 {
            count += 1
        }
        return count
    }

    private func drawLabel(
        _ string: String,
        atY yPos: CGFloat,
        attrs: [NSAttributedString.Key: Any],
        scrollOffset: CGFloat
    ) {
        let attrString = NSAttributedString(string: string, attributes: attrs)
        let size = attrString.size()
        let xPos = ruleThickness - size.width - 7
        attrString.draw(at: NSPoint(x: max(4, xPos), y: yPos - scrollOffset))
    }
}
