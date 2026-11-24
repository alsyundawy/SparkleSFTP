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
    var onFocusRequested: (() -> Void)?
    var onDropFiles: (([URL]) -> Void)?

    private(set) var isScrollingActive = false
    private var pendingMouseDownEvent: NSEvent?
    private var dragStartPoint: NSPoint = .zero
    var isDraggingSelection = false
    private let dragMovementThreshold: CGFloat = 10.0
    private var selectionAnchorRow: Int = -1
    private var scrollResetWorkItem: DispatchWorkItem?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: options) {
            return .copy
        }
        return []
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: options) {
            return .copy
        }
        return []
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let urls = (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL])?
            .filter(\.isFileURL),
            !urls.isEmpty else {
            return false
        }
        onDropFiles?(urls)
        return true
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        NotificationCenter.default.removeObserver(self, name: NSScrollView.willStartLiveScrollNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSScrollView.didEndLiveScrollNotification, object: nil)

        if let scrollView = enclosingScrollView {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleLiveScrollDidStart),
                name: NSScrollView.willStartLiveScrollNotification,
                object: scrollView
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleLiveScrollDidEnd),
                name: NSScrollView.didEndLiveScrollNotification,
                object: scrollView
            )
        }
    }

    override func viewWillMove(toSuperview newSuperview: NSView?) {
        super.viewWillMove(toSuperview: newSuperview)
        if newSuperview == nil {
            NotificationCenter.default.removeObserver(
                self,
                name: NSScrollView.willStartLiveScrollNotification,
                object: nil
            )
            NotificationCenter.default.removeObserver(
                self,
                name: NSScrollView.didEndLiveScrollNotification,
                object: nil
            )
            scrollResetWorkItem?.cancel()
            isScrollingActive = false
            pendingMouseDownEvent = nil
            isDraggingSelection = false
        }
    }

    @objc private func handleLiveScrollDidStart() {
        isScrollingActive = true
        pendingMouseDownEvent = nil
        isDraggingSelection = false
        clearAllRowHovers()
    }

    @objc private func handleLiveScrollDidEnd() {
        isScrollingActive = false
        clearAllRowHovers()
    }

    func clearAllRowHovers() {
        enumerateAvailableRowViews { rowView, _ in
            (rowView as? RowHoverControllable)?.clearHover()
        }
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        onFocusRequested?()
        let localPoint = convert(event.locationInWindow, from: nil)
        let hitRow = row(at: localPoint)

        if hitRow == -1 {
            deselectAll(nil)
            selectionAnchorRow = -1
            pendingMouseDownEvent = nil
            isDraggingSelection = false
            onContextActionShortcut?(.deselectAll)
            return
        }

        if event.clickCount >= 2 {
            pendingMouseDownEvent = nil
            isDraggingSelection = false
            super.mouseDown(with: event)
            return
        }

        // Defer selection until mouseUp to prevent trackpad tap-to-click gestures from
        // accidentally triggering AppKit drag-selection during two-finger scrolling.
        pendingMouseDownEvent = event
        dragStartPoint = localPoint
        isDraggingSelection = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !isScrollingActive, let pendingEvent = pendingMouseDownEvent else { return }
        let currentPoint = convert(event.locationInWindow, from: nil)
        let deltaX = abs(currentPoint.x - dragStartPoint.x)
        let deltaY = abs(currentPoint.y - dragStartPoint.y)

        // If movement is predominantly vertical without Command or Shift modifier,
        // treat it as trackpad scrolling gesture rather than row selection drag.
        if deltaY > deltaX * 1.2, !pendingEvent.modifierFlags.contains([.command, .shift]) {
            pendingMouseDownEvent = nil
            isDraggingSelection = false
            return
        }

        // Range drag-selection is strictly reserved for intentional Command or Shift modifier holds
        guard pendingEvent.modifierFlags.contains([.command, .shift]) else {
            return
        }

        let distance = hypot(deltaX, deltaY)
        if !isDraggingSelection {
            guard distance >= dragMovementThreshold else { return }
            isDraggingSelection = true
        }

        let startRow = row(at: dragStartPoint)
        let currentRow = row(at: currentPoint)
        guard startRow >= 0, currentRow >= 0 else { return }

        let minRow = min(startRow, currentRow)
        let maxRow = max(startRow, currentRow)
        let targetIndexes = IndexSet(integersIn: minRow ... maxRow)

        if pendingEvent.modifierFlags.contains(.command) {
            selectRowIndexes(selectedRowIndexes.union(targetIndexes), byExtendingSelection: false)
        } else {
            selectRowIndexes(targetIndexes, byExtendingSelection: false)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if let pendingEvent = pendingMouseDownEvent, !isDraggingSelection {
            let localPoint = convert(event.locationInWindow, from: nil)
            let distance = hypot(localPoint.x - dragStartPoint.x, localPoint.y - dragStartPoint.y)
            let hitRow = row(at: localPoint)
            if distance < dragMovementThreshold, hitRow >= 0 {
                applyClickSelection(forRow: hitRow, modifiers: pendingEvent.modifierFlags)
            }
        }
        pendingMouseDownEvent = nil
        isDraggingSelection = false
        super.mouseUp(with: event)
    }

    private func applyClickSelection(forRow hitRow: Int, modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.command) {
            if isRowSelected(hitRow) {
                deselectRow(hitRow)
            } else {
                selectRowIndexes(IndexSet(integer: hitRow), byExtendingSelection: true)
            }
            selectionAnchorRow = hitRow
        } else if modifiers.contains(.shift) {
            let anchor = (selectionAnchorRow >= 0 && selectionAnchorRow < numberOfRows)
                ? selectionAnchorRow
                : (selectedRow >= 0 ? selectedRow : hitRow)
            let minRow = min(anchor, hitRow)
            let maxRow = max(anchor, hitRow)
            selectRowIndexes(IndexSet(integersIn: minRow ... maxRow), byExtendingSelection: false)
        } else {
            selectRowIndexes(IndexSet(integer: hitRow), byExtendingSelection: false)
            selectionAnchorRow = hitRow
        }
    }

    override func scrollWheel(with event: NSEvent) {
        // Trackpad scrolling immediately cancels pending mouse clicks and drag selections
        pendingMouseDownEvent = nil
        isDraggingSelection = false
        isScrollingActive = true
        clearAllRowHovers()
        scrollResetWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.isScrollingActive = false
            self?.clearAllRowHovers()
        }
        scrollResetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20, execute: workItem)
        super.scrollWheel(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        onFocusRequested?()
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
        case #selector(deselectAll(_:)):
            return !selectedRowIndexes.isEmpty
        case #selector(copy(_:)), #selector(delete(_:)):
            return !selectedRowIndexes.isEmpty
        default:
            return super.validateUserInterfaceItem(item)
        }
    }

    override func selectAll(_: Any?) {
        onContextActionShortcut?(.selectAll)
    }

    override func deselectAll(_ sender: Any?) {
        super.deselectAll(sender)
        onContextActionShortcut?(.deselectAll)
    }

    @objc func copy(_: Any?) {
        onContextActionShortcut?(.copyClipboard)
    }

    @objc func delete(_: Any?) {
        onContextActionShortcut?(.delete)
    }
}

@MainActor
protocol RowHoverControllable: AnyObject {
    func clearHover()
}

final class ThemedFileRowView: NSTableRowView, RowHoverControllable {
    var highlightColor = NSColor.selectedContentBackgroundColor
    var hoverColor = NSColor.labelColor.withAlphaComponent(0.08)
    var accentIndicatorColor = NSColor.controlAccentColor
    private var hoverTrackingArea: NSTrackingArea?
    private var isHovered = false {
        didSet {
            if oldValue != isHovered {
                needsDisplay = true
            }
        }
    }

    private var enclosingTableView: InteractiveFileTableView? {
        var view: NSView? = superview
        while let current = view {
            if let table = current as? InteractiveFileTableView {
                return table
            }
            view = current.superview
        }
        return nil
    }

    func clearHover() {
        guard isHovered else { return }
        isHovered = false
        needsDisplay = true
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
        if let table = enclosingTableView, table.isScrollingActive {
            isHovered = false
            return
        }
        isHovered = true
        super.mouseEntered(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        super.mouseExited(with: event)
    }

    override func drawBackground(in dirtyRect: NSRect) {
        super.drawBackground(in: dirtyRect)
        if let table = enclosingTableView, table.isScrollingActive {
            return
        }
        guard !isSelected, isHovered else { return }
        hoverColor.setFill()
        let hoverRect = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: hoverRect, xRadius: 3, yRadius: 3)
        path.fill()
    }

    override func drawSelection(in _: NSRect) {
        guard selectionHighlightStyle != .none, isSelected else { return }
        let selectionRect = bounds.insetBy(dx: 1, dy: 0.5)
        let fillPath = NSBezierPath(roundedRect: selectionRect, xRadius: 3, yRadius: 3)
        highlightColor.setFill()
        fillPath.fill()

        // 3.5px prominent left accent strip to make selected files & folders crystal clear
        let barColor = isEmphasized ? accentIndicatorColor : accentIndicatorColor.withAlphaComponent(0.6)
        barColor.setFill()
        let barRect = NSRect(x: bounds.minX + 1, y: bounds.minY + 1.5, width: 3.5, height: bounds.height - 3)
        let barPath = NSBezierPath(roundedRect: barRect, xRadius: 1.75, yRadius: 1.75)
        barPath.fill()
    }
}
