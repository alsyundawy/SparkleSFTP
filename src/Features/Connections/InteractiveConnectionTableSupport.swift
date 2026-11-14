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

    private(set) var isScrollingActive = false
    private var pendingMouseDownEvent: NSEvent?
    private var dragStartPoint: NSPoint = .zero
    var isDraggingSelection = false
    private let dragMovementThreshold: CGFloat = 10.0
    private var selectionAnchorRow: Int = -1
    private var scrollResetWorkItem: DispatchWorkItem?

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
        let localPoint = convert(event.locationInWindow, from: nil)
        let hitRow = row(at: localPoint)

        if hitRow == -1 {
            deselectAll(nil)
            selectionAnchorRow = -1
            pendingMouseDownEvent = nil
            isDraggingSelection = false
            return
        }

        if event.clickCount >= 2 {
            pendingMouseDownEvent = nil
            isDraggingSelection = false
            super.mouseDown(with: event)
            return
        }

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
}
