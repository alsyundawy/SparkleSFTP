import AppKit
import SparkleDesignSystem
import SwiftUI

struct TabBarActionButtonModel: Equatable {
    let title: String?
    let symbolName: String
    let tooltip: String
    let accessibilityID: String
    let isActive: Bool
}

@MainActor
final class TabBarActionButton: NSButton {
    var onHoverChanged: ((Bool) -> Void)?
    private var hoverArea: NSTrackingArea?

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }

    override var intrinsicContentSize: NSSize {
        let base = super.intrinsicContentSize
        let widthPadding: CGFloat = title.isEmpty ? 12 : 18
        return NSSize(width: ceil(max(base.width + widthPadding, 26)), height: 26)
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

struct TabBarActionButtonRepresentable: NSViewRepresentable {
    let model: TabBarActionButtonModel
    let palette: SparkleThemePalette
    let action: @MainActor () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action, model: model, palette: palette)
    }

    func makeNSView(context: Context) -> TabBarActionButton {
        let button = TabBarActionButton()
        button.isBordered = false
        button.wantsLayer = true
        button.target = context.coordinator
        button.action = #selector(Coordinator.handleClick)
        button.setButtonType(.momentaryPushIn)
        button.onHoverChanged = { [weak coordinator = context.coordinator, weak button] hovered in
            guard let coordinator, let button else { return }
            coordinator.isHovered = hovered
            coordinator.applyStyle(to: button)
        }
        context.coordinator.applyStyle(to: button)
        return button
    }

    func updateNSView(_ button: TabBarActionButton, context: Context) {
        context.coordinator.action = action
        context.coordinator.model = model
        context.coordinator.palette = palette
        context.coordinator.applyStyle(to: button)
    }

    func sizeThatFits(_: ProposedViewSize, nsView button: TabBarActionButton, context _: Context) -> CGSize? {
        button.intrinsicContentSize
    }

    @MainActor
    final class Coordinator: NSObject {
        var action: @MainActor () -> Void
        var model: TabBarActionButtonModel
        var palette: SparkleThemePalette
        var isHovered = false

        init(action: @escaping @MainActor () -> Void, model: TabBarActionButtonModel, palette: SparkleThemePalette) {
            self.action = action
            self.model = model
            self.palette = palette
        }

        @objc func handleClick() {
            action()
        }

        func applyStyle(to button: TabBarActionButton) {
            let accent = NSColor(hex: palette.accentHex)
            let primary = NSColor(hex: palette.primaryTextHex)
            let secondary = NSColor(hex: palette.secondaryTextHex)
            let border = NSColor(hex: palette.borderHex)
            let canvas = NSColor(hex: palette.canvasHex)
            let tint = model.isActive ? accent : (isHovered ? primary : secondary)

            let previousTitle = button.title
            button.toolTip = model.tooltip
            button.setAccessibilityIdentifier(model.accessibilityID)
            button.setAccessibilityLabel(model.tooltip)
            button.font = NSFont.systemFont(ofSize: 11, weight: model.isActive ? .semibold : .medium)
            button.image = NSImage(systemSymbolName: model.symbolName, accessibilityDescription: model.tooltip)
            button.contentTintColor = tint
            button.imageHugsTitle = true

            if let title = model.title, !title.isEmpty {
                button.imagePosition = .imageLeading
                button.attributedTitle = NSAttributedString(
                    string: title,
                    attributes: [
                        .font: button.font ?? NSFont.systemFont(ofSize: 11, weight: .medium),
                        .foregroundColor: tint
                    ]
                )
            } else {
                button.imagePosition = .imageOnly
                button.title = ""
            }

            button.layer?.cornerRadius = 6
            button.layer?.borderWidth = 1
            button.layer?.borderColor = (model.isActive ? accent.withAlphaComponent(0.75) : border).cgColor
            if model.isActive {
                button.layer?.backgroundColor = accent.withAlphaComponent(palette.isDark ? 0.24 : 0.14).cgColor
            } else if isHovered {
                button.layer?.backgroundColor = accent.withAlphaComponent(palette.isDark ? 0.14 : 0.08).cgColor
            } else {
                button.layer?.backgroundColor = canvas.cgColor
            }
            if previousTitle != (model.title ?? "") {
                button.invalidateIntrinsicContentSize()
            }
        }
    }
}
