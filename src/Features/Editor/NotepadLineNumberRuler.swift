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

    private var cachedNewlineOffsets: [Int] = []
    private var lastIndexedLength: Int = -1
    private var needsReindex = true

    init(scrollView: NSScrollView, textView: NSTextView) {
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 44
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTextChanged(_:)),
            name: NSText.didChangeNotification,
            object: textView
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleBoundsChanged(_:)),
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

    @objc private func handleTextChanged(_: Notification) {
        needsReindex = true
        needsDisplay = true
    }

    @objc private func handleBoundsChanged(_: Notification) {
        needsDisplay = true
    }

    override func drawHashMarksAndLabels(in _: NSRect) {
        guard let textView = clientView as? NSTextView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer
        else { return }

        let nsText = textView.string as NSString
        rebuildNewlineIndexIfNeeded(for: nsText)
        updateThickness(for: cachedNewlineOffsets.count + 1)
        drawGutterBackground()

        let visibleRect = scrollView?.contentView.bounds ?? textView.visibleRect
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        if nsText.length == 0 {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: max(10, font.pointSize - 1), weight: .regular),
                .foregroundColor: NSColor(hex: palette.secondaryTextHex)
            ]
            drawLabel("1", atY: textView.textContainerOrigin.y, attrs: attrs, scrollOffset: visibleRect.origin.y)
            return
        }

        renderLineNumbers(
            textView: textView,
            layoutManager: layoutManager,
            charRange: charRange,
            visibleRect: visibleRect
        )
    }

    private func updateThickness(for lineCount: Int) {
        let requiredDigits = max(3, String(lineCount).count)
        let dynamicThickness = max(44, CGFloat(requiredDigits * 9 + 18))
        if abs(ruleThickness - dynamicThickness) > 0.5 {
            ruleThickness = dynamicThickness
        }
    }

    private func drawGutterBackground() {
        NSColor(hex: palette.windowHex).setFill()
        bounds.fill()
        NSColor(hex: palette.borderHex).setFill()
        NSRect(x: bounds.width - 1, y: 0, width: 1, height: bounds.height).fill()
    }

    private func renderLineNumbers(
        textView: NSTextView,
        layoutManager: NSLayoutManager,
        charRange: NSRange,
        visibleRect: NSRect
    ) {
        let nsText = textView.string as NSString
        let containerOriginY = textView.textContainerOrigin.y
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: max(10, font.pointSize - 1), weight: .regular),
            .foregroundColor: NSColor(hex: palette.secondaryTextHex)
        ]
        var lineNumber = countNewlines(upTo: charRange.location) + 1
        var index = charRange.location
        let maxIndex = min(nsText.length, charRange.location + charRange.length)

        while index <= maxIndex, index < nsText.length {
            let lineRange = nsText.lineRange(for: NSRange(location: min(index, nsText.length), length: 0))
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: lineRange.location)
            guard glyphIndex < layoutManager.numberOfGlyphs else { break }
            var lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            lineRect.origin.y += containerOriginY
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

    private func rebuildNewlineIndexIfNeeded(for text: NSString) {
        let length = text.length
        guard needsReindex || length != lastIndexedLength else { return }
        needsReindex = false
        lastIndexedLength = length

        guard length > 0 else {
            cachedNewlineOffsets.removeAll(keepingCapacity: true)
            return
        }

        var offsets: [Int] = []
        offsets.reserveCapacity(min(16_384, length / 40))
        var index = 0
        while index < length {
            let searchRange = NSRange(location: index, length: length - index)
            let found = text.range(of: "\n", options: .literal, range: searchRange)
            guard found.location != NSNotFound else { break }
            offsets.append(found.location)
            index = found.location + 1
        }
        cachedNewlineOffsets = offsets
    }

    private func countNewlines(upTo limit: Int) -> Int {
        guard limit > 0, !cachedNewlineOffsets.isEmpty else { return 0 }
        var low = 0
        var high = cachedNewlineOffsets.count
        while low < high {
            let mid = low + (high - low) / 2
            if cachedNewlineOffsets[mid] < limit {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
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
