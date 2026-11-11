import AppKit
import Foundation
import SparkleDesignSystem

final class NonMovingTabScrollView: NSScrollView {
    override var mouseDownCanMoveWindow: Bool {
        false
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 34)
    }

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        (documentView as? TabStripDocumentView)?.layoutForContainerWidth(newSize.width)
    }
}

final class TabStripDocumentView: NSView {
    override var isFlipped: Bool {
        true
    }

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }

    func layoutForContainerWidth(_ containerWidth: CGFloat) {
        let rowHeight: CGFloat = 26
        let topMargin: CGFloat = 4
        var cursorX: CGFloat = 2
        for case let chip as WorkspaceTabChipView in subviews {
            let width = chip.preferredWidth()
            chip.frame = NSRect(x: cursorX, y: topMargin, width: width, height: rowHeight)
            cursorX += width + 4
        }
        let targetWidth = max(containerWidth, cursorX + 2)
        frame = NSRect(x: 0, y: 0, width: targetWidth, height: 34)
    }
}

final class TabCloseButton: NSButton {
    var onHoverChanged: ((Bool) -> Void)?
    private var hoverArea: NSTrackingArea?

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea {
            removeTrackingArea(hoverArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChanged?(true)
        super.mouseEntered(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged?(false)
        super.mouseExited(with: event)
    }
}

final class WorkspaceTabChipView: NSView {
    let tabID: UUID
    let closeButton = TabCloseButton()

    private let dotView = NSView()
    private let iconView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private var hoverArea: NSTrackingArea?
    private var isHovered = false
    private var isCloseHovered = false
    private var currentItem: WorkspaceTabStripItem
    private var currentPalette: SparkleThemePalette

    var onSelect: (() -> Void)?
    var onClose: (() -> Void)?
    var menuBuilder: (() -> NSMenu)?

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }

    init(item: WorkspaceTabStripItem, palette: SparkleThemePalette) {
        tabID = item.id
        currentItem = item
        currentPalette = palette
        super.init(frame: .zero)
        wantsLayer = true
        setupSubviews()
        apply(item: item, palette: palette)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    private func setupSubviews() {
        dotView.wantsLayer = true
        addSubview(dotView)

        iconView.imageScaling = .scaleProportionallyDown
        addSubview(iconView)

        titleField.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        titleField.lineBreakMode = .byTruncatingTail
        titleField.maximumNumberOfLines = 1
        titleField.isSelectable = false
        titleField.isEditable = false
        titleField.drawsBackground = false
        titleField.isBordered = false
        addSubview(titleField)

        closeButton.isBordered = false
        closeButton.bezelStyle = .shadowlessSquare
        closeButton.title = ""
        closeButton.imagePosition = .imageOnly
        closeButton.target = self
        closeButton.action = #selector(handleCloseClicked)
        closeButton.wantsLayer = true
        closeButton.layer?.cornerRadius = 4
        closeButton.onHoverChanged = { [weak self] hovered in
            self?.isCloseHovered = hovered
            self?.updateAppearance()
        }
        addSubview(closeButton)
    }

    @objc private func handleCloseClicked() {
        onClose?()
    }

    func apply(item: WorkspaceTabStripItem, palette: SparkleThemePalette) {
        currentItem = item
        currentPalette = palette
        let displayText = if item.isActive, let subtitle = item.subtitle, !subtitle.isEmpty {
            "\(item.title) \(subtitle)"
        } else {
            item.title
        }
        titleField.stringValue = displayText
        titleField.font = NSFont.systemFont(
            ofSize: NSFont.smallSystemFontSize,
            weight: item.isActive ? .semibold : .regular
        )
        titleField.textColor = NSColor(hex: palette.primaryTextHex)
        toolTip = displayText

        let iconName = item.isConnected
            ? (item.isEncrypted ? SparkleTheme.Symbols.sftp : SparkleTheme.Symbols.ftpInsecure)
            : "bolt.horizontal"
        let iconTint = item.isConnected
            ? (item.isEncrypted ? NSColor(hex: palette.accentHex) : NSColor.systemRed)
            : NSColor(hex: palette.secondaryTextHex)
        iconView.image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)
        iconView.contentTintColor = iconTint

        closeButton.isHidden = !item.canClose
        setAccessibilityIdentifier("workspace-tab-\(item.id.uuidString)")
        setAccessibilityLabel(item.title)
        closeButton.setAccessibilityIdentifier("workspace-tab-close-\(item.id.uuidString)")
        updateAppearance()
        needsLayout = true
    }

    func preferredWidth() -> CGFloat {
        let textWidth = (titleField.stringValue as NSString).size(
            withAttributes: [.font: titleField.font ?? NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)]
        ).width
        let closeReserve: CGFloat = currentItem.canClose ? 24 : 8
        let computed = ceil(textWidth) + 38 + closeReserve
        return min(max(computed, 96), 236)
    }

    override func layout() {
        super.layout()
        let midY = bounds.midY
        dotView.frame = NSRect(x: 8, y: midY - 3, width: 6, height: 6)
        dotView.layer?.cornerRadius = 3
        iconView.frame = NSRect(x: 18, y: midY - 7, width: 14, height: 14)

        let rightInset: CGFloat
        if currentItem.canClose {
            closeButton.frame = NSRect(x: bounds.width - 24, y: midY - 10, width: 20, height: 20)
            rightInset = 26
        } else {
            closeButton.frame = .zero
            rightInset = 8
        }
        let titleX: CGFloat = 35
        let titleWidth = max(20, bounds.width - titleX - rightInset)
        titleField.frame = NSRect(x: titleX, y: midY - 8, width: titleWidth, height: 16)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        if !closeButton.isHidden, closeButton.frame.contains(local) {
            return closeButton
        }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        guard event.type == .leftMouseDown else {
            super.mouseDown(with: event)
            return
        }
        onSelect?()
    }

    override func menu(for _: NSEvent) -> NSMenu? {
        menuBuilder?()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea {
            removeTrackingArea(hoverArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateAppearance()
        super.mouseEntered(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateAppearance()
        super.mouseExited(with: event)
    }

    private func updateAppearance() {
        let accent = NSColor(hex: currentPalette.accentHex)
        let border = NSColor(hex: currentPalette.borderHex)
        let canvas = NSColor(hex: currentPalette.canvasHex)
        let secondary = NSColor(hex: currentPalette.secondaryTextHex)

        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.borderColor = (currentItem.isActive ? accent.withAlphaComponent(0.85) : border).cgColor
        if currentItem.isActive {
            layer?.backgroundColor = accent.withAlphaComponent(currentPalette.isDark ? 0.30 : 0.18).cgColor
        } else if isHovered {
            layer?.backgroundColor = accent.withAlphaComponent(currentPalette.isDark ? 0.14 : 0.08).cgColor
        } else {
            layer?.backgroundColor = canvas.cgColor
        }

        dotView.layer?.backgroundColor = (
            currentItem.isConnected ? NSColor.systemGreen : secondary.withAlphaComponent(0.45)
        ).cgColor

        let closeSymbol = isCloseHovered ? "xmark.circle.fill" : "xmark"
        closeButton.image = NSImage(systemSymbolName: closeSymbol, accessibilityDescription: nil)
        closeButton.contentTintColor = isCloseHovered
            ? NSColor(hex: currentPalette.primaryTextHex)
            : secondary
        closeButton.layer?.backgroundColor = isCloseHovered
            ? secondary.withAlphaComponent(0.18).cgColor
            : NSColor.clear.cgColor
    }
}
