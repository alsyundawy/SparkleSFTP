import AppKit
@testable import SparkleCore
@testable import SparkleDesignSystem
@testable import SparkleFeatures
import Testing

@Suite("Interactive Table Touchpad Scroll & Selection Tests")
struct InteractiveTableScrollGuardTests {
    @Test("InteractiveFileTableView scrollWheel activates scrolling guard and cancels pending selection")
    @MainActor
    func interactiveTableScrollCancelsPendingSelection() throws {
        _ = NSApplication.shared
        let table = InteractiveFileTableView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        table.addTableColumn(column)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        scroll.documentView = table
        table.viewDidMoveToSuperview()

        #expect(!table.isScrollingActive)

        let cgEvent = try #require(
            CGEvent(
                scrollWheelEvent2Source: nil,
                units: .pixel,
                wheelCount: 1,
                wheel1: -10,
                wheel2: 0,
                wheel3: 0
            )
        )
        let scrollEvt = try #require(NSEvent(cgEvent: cgEvent))
        table.scrollWheel(with: scrollEvt)
        #expect(table.isScrollingActive)
    }

    @Test("Vertical drag without modifiers is treated as trackpad scroll gesture and does not select rows")
    @MainActor
    func verticalDragWithoutModifiersDiscardsSelection() throws {
        _ = NSApplication.shared
        let table = InteractiveFileTableView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        table.addTableColumn(column)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        scroll.documentView = table
        table.viewDidMoveToSuperview()

        let downPoint = NSPoint(x: 50, y: 50)
        let dragPoint = NSPoint(x: 52, y: 120) // Predominantly vertical movement (70pt down, 2pt horizontal)

        let downEvt = try #require(
            NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: downPoint,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 1,
                clickCount: 1,
                pressure: 1.0
            )
        )
        let dragEvt = try #require(
            NSEvent.mouseEvent(
                with: .leftMouseDragged,
                location: dragPoint,
                modifierFlags: [],
                timestamp: 0.01,
                windowNumber: 0,
                context: nil,
                eventNumber: 2,
                clickCount: 1,
                pressure: 1.0
            )
        )

        table.mouseDown(with: downEvt)
        table.mouseDragged(with: dragEvt)
        #expect(!table.isDraggingSelection)
        #expect(table.selectedRowIndexes.isEmpty)
    }

    @Test("InteractiveConnectionTableView vertical drag without modifiers discards selection")
    @MainActor
    func connectionVerticalDragWithoutModifiersDiscardsSelection() throws {
        _ = NSApplication.shared
        let table = InteractiveConnectionTableView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("conn"))
        table.addTableColumn(column)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        scroll.documentView = table
        table.viewDidMoveToSuperview()

        let downPoint = NSPoint(x: 50, y: 50)
        let dragPoint = NSPoint(x: 51, y: 130)

        let downEvt = try #require(
            NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: downPoint,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 1,
                clickCount: 1,
                pressure: 1.0
            )
        )
        let dragEvt = try #require(
            NSEvent.mouseEvent(
                with: .leftMouseDragged,
                location: dragPoint,
                modifierFlags: [],
                timestamp: 0.01,
                windowNumber: 0,
                context: nil,
                eventNumber: 2,
                clickCount: 1,
                pressure: 1.0
            )
        )

        table.mouseDown(with: downEvt)
        table.mouseDragged(with: dragEvt)
        #expect(!table.isDraggingSelection)
        #expect(table.selectedRowIndexes.isEmpty)
    }

    @Test("InteractiveConnectionTableView scrollWheel activates scrolling guard")
    @MainActor
    func interactiveConnectionTableScrollGuard() throws {
        _ = NSApplication.shared
        let table = InteractiveConnectionTableView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("conn"))
        table.addTableColumn(column)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        scroll.documentView = table
        table.viewDidMoveToSuperview()

        #expect(!table.isScrollingActive)

        let cgEvent = try #require(
            CGEvent(
                scrollWheelEvent2Source: nil,
                units: .pixel,
                wheelCount: 1,
                wheel1: -10,
                wheel2: 0,
                wheel3: 0
            )
        )
        let scrollEvt = try #require(NSEvent(cgEvent: cgEvent))
        table.scrollWheel(with: scrollEvt)
        #expect(table.isScrollingActive)
    }
}
