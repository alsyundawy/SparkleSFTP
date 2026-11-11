import AppKit
import Foundation
import SparkleCore
import SparkleDesignSystem
import SwiftUI

struct WorkspaceTabStripItem: Equatable {
    let id: UUID
    let title: String
    let subtitle: String?
    let isConnected: Bool
    let isEncrypted: Bool
    let isActive: Bool
    let canClose: Bool
    let canCloseOthers: Bool
}

struct WorkspaceTabStripRepresentable: NSViewRepresentable {
    let items: [WorkspaceTabStripItem]
    let activeTabID: UUID
    let palette: SparkleThemePalette
    let strings: AppStrings
    let onSelect: (UUID) -> Void
    let onClose: (UUID) -> Void
    let onNewTab: () -> Void
    let onDuplicateTab: (UUID) -> Void
    let onReconnectTab: (UUID) -> Void
    let onOpenNewWindow: (UUID) -> Void
    let onCloseOtherTabs: (UUID) -> Void

    func makeCoordinator() -> WorkspaceTabStripCoordinator {
        WorkspaceTabStripCoordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NonMovingTabScrollView()
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.horizontalScrollElasticity = .none
        scrollView.verticalScrollElasticity = .none
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.clipsToBounds = true

        let docView = TabStripDocumentView()
        scrollView.documentView = docView
        context.coordinator.scrollView = scrollView
        context.coordinator.documentView = docView
        context.coordinator.reload(items: items, activeTabID: activeTabID, palette: palette)
        return scrollView
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView _: NSScrollView,
        context _: Context
    ) -> CGSize? {
        let proposedWidth = proposal.width ?? 360
        return CGSize(width: max(proposedWidth, 120), height: 34)
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        let itemsChanged = context.coordinator.cachedItems != items
        let activeChanged = context.coordinator.cachedActiveID != activeTabID
        let paletteChanged = context.coordinator.cachedPalette != palette
        let docHeightChanged = abs((context.coordinator.documentView?.frame.height ?? 0) - scrollView.bounds.height) > 1
        if itemsChanged || activeChanged || paletteChanged || docHeightChanged {
            context.coordinator.reload(items: items, activeTabID: activeTabID, palette: palette)
        }
    }
}

@MainActor
final class WorkspaceTabStripCoordinator: NSObject {
    var parent: WorkspaceTabStripRepresentable
    var cachedItems: [WorkspaceTabStripItem] = []
    var cachedActiveID: UUID?
    var cachedPalette: SparkleThemePalette?
    weak var scrollView: NSScrollView?
    weak var documentView: TabStripDocumentView?
    private var chipViews: [UUID: WorkspaceTabChipView] = [:]
    private var contextMenuTargetID: UUID?

    init(parent: WorkspaceTabStripRepresentable) {
        self.parent = parent
    }

    func reload(items: [WorkspaceTabStripItem], activeTabID: UUID, palette: SparkleThemePalette) {
        cachedItems = items
        cachedActiveID = activeTabID
        cachedPalette = palette
        guard let documentView, let scrollView else { return }

        let validIDs = Set(items.map(\.id))
        for (existingID, view) in chipViews where !validIDs.contains(existingID) {
            view.removeFromSuperview()
            chipViews.removeValue(forKey: existingID)
        }

        var orderedChips: [WorkspaceTabChipView] = []
        for item in items {
            let chip = chipViews[item.id] ?? WorkspaceTabChipView(item: item, palette: palette)
            chip.apply(item: item, palette: palette)
            let itemID = item.id
            chip.onSelect = { [weak self] in self?.parent.onSelect(itemID) }
            chip.onClose = { [weak self] in self?.parent.onClose(itemID) }
            chip.menuBuilder = { [weak self] in self?.buildContextMenu(for: item) ?? NSMenu() }
            chipViews[item.id] = chip
            orderedChips.append(chip)
        }
        documentView.subviews = orderedChips
        documentView.layoutForContainerWidth(scrollView.bounds.width)

        if let activeChip = chipViews[activeTabID] {
            documentView.scrollToVisible(activeChip.frame.insetBy(dx: -8, dy: 0))
        }
    }

    private func buildContextMenu(for item: WorkspaceTabStripItem) -> NSMenu {
        contextMenuTargetID = item.id
        let strings = parent.strings
        let menu = NSMenu()
        menu.addItem(makeMenuItem(title: strings.t("tabs.newTab"), action: #selector(handleNewTab)))
        menu.addItem(makeMenuItem(title: strings.t("tabs.duplicateTab"), action: #selector(handleDuplicateTab)))
        if item.isConnected {
            menu.addItem(makeMenuItem(title: strings.t("tabs.reconnect"), action: #selector(handleReconnectTab)))
            menu.addItem(
                makeMenuItem(title: strings.t("conn.connectNewWindow"), action: #selector(handleOpenNewWindow))
            )
        }
        menu.addItem(NSMenuItem.separator())
        let closeItem = makeMenuItem(title: strings.t("tabs.closeTab"), action: #selector(handleCloseTab))
        closeItem.isEnabled = item.canClose
        menu.addItem(closeItem)
        let closeOthersItem = makeMenuItem(
            title: strings.t("tabs.closeOtherTabs"),
            action: #selector(handleCloseOtherTabs)
        )
        closeOthersItem.isEnabled = item.canCloseOthers
        menu.addItem(closeOthersItem)
        return menu
    }

    private func makeMenuItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func handleNewTab() {
        parent.onNewTab()
    }

    @objc private func handleDuplicateTab() {
        if let id = contextMenuTargetID {
            parent.onDuplicateTab(id)
        }
    }

    @objc private func handleReconnectTab() {
        if let id = contextMenuTargetID {
            parent.onReconnectTab(id)
        }
    }

    @objc private func handleOpenNewWindow() {
        if let id = contextMenuTargetID {
            parent.onOpenNewWindow(id)
        }
    }

    @objc private func handleCloseTab() {
        if let id = contextMenuTargetID {
            parent.onClose(id)
        }
    }

    @objc private func handleCloseOtherTabs() {
        if let id = contextMenuTargetID {
            parent.onCloseOtherTabs(id)
        }
    }
}
