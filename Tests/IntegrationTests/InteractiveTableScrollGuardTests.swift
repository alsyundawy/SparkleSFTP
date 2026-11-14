import AppKit
@testable import SparkleCore
@testable import SparkleDesignSystem
@testable import SparkleFeatures
import Testing

@Suite("Interactive Table Touchpad Scroll & Selection Tests")
struct InteractiveTableScrollGuardTests {
    @Test("InteractiveFileTableView scrollWheel activates scrolling guard and cancels pending selection")
    @MainActor
    func interactiveTableScrollCancelsPendingSelection() {
        _ = NSApplication.shared
        let table = InteractiveFileTableView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        table.addTableColumn(column)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        scroll.documentView = table
        table.viewDidMoveToSuperview()

        #expect(!table.isScrollingActive)

        if let cgEvent = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 1,
            wheel1: -10,
            wheel2: 0,
            wheel3: 0
        ), let scrollEvt = NSEvent(cgEvent: cgEvent) {
            table.scrollWheel(with: scrollEvt)
            #expect(table.isScrollingActive)
        }
    }

    @Test("Vertical drag without modifiers is treated as trackpad scroll gesture and does not select rows")
    @MainActor
    func verticalDragWithoutModifiersDiscardsSelection() {
        _ = NSApplication.shared
        let table = InteractiveFileTableView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        table.addTableColumn(column)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        scroll.documentView = table
        table.viewDidMoveToSuperview()

        let downPoint = CGPoint(x: 50, y: 50)
        let dragPoint = CGPoint(x: 52, y: 120) // Predominantly vertical movement (70pt down, 2pt horizontal)

        let downCG = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: downPoint,
            mouseButton: .left
        )
        let dragCG = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDragged,
            mouseCursorPosition: dragPoint,
            mouseButton: .left
        )

        if let downCG, let downEvt = NSEvent(cgEvent: downCG),
           let dragCG, let dragEvt = NSEvent(cgEvent: dragCG) {
            table.mouseDown(with: downEvt)
            table.mouseDragged(with: dragEvt)
            #expect(!table.isDraggingSelection)
            #expect(table.selectedRowIndexes.isEmpty)
        }
    }

    @Test("InteractiveConnectionTableView vertical drag without modifiers discards selection")
    @MainActor
    func connectionVerticalDragWithoutModifiersDiscardsSelection() {
        _ = NSApplication.shared
        let table = InteractiveConnectionTableView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("conn"))
        table.addTableColumn(column)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        scroll.documentView = table
        table.viewDidMoveToSuperview()

        let downPoint = CGPoint(x: 50, y: 50)
        let dragPoint = CGPoint(x: 51, y: 130)

        let downCG = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: downPoint,
            mouseButton: .left
        )
        let dragCG = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDragged,
            mouseCursorPosition: dragPoint,
            mouseButton: .left
        )

        if let downCG, let downEvt = NSEvent(cgEvent: downCG),
           let dragCG, let dragEvt = NSEvent(cgEvent: dragCG) {
            table.mouseDown(with: downEvt)
            table.mouseDragged(with: dragEvt)
            #expect(!table.isDraggingSelection)
            #expect(table.selectedRowIndexes.isEmpty)
        }
    }

    @Test("InteractiveConnectionTableView scrollWheel activates scrolling guard")
    @MainActor
    func interactiveConnectionTableScrollGuard() {
        _ = NSApplication.shared
        let table = InteractiveConnectionTableView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("conn"))
        table.addTableColumn(column)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        scroll.documentView = table
        table.viewDidMoveToSuperview()

        #expect(!table.isScrollingActive)

        if let cgEvent = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 1,
            wheel1: -10,
            wheel2: 0,
            wheel3: 0
        ), let scrollEvt = NSEvent(cgEvent: cgEvent) {
            table.scrollWheel(with: scrollEvt)
            #expect(table.isScrollingActive)
        }
    }
}
