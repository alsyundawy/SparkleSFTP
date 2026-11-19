import AppKit
import SparkleDesignSystem
import SwiftUI

/// Item definition for standard Commander function key actions (F3–F8).
struct FunctionKeyAction: Identifiable {
    let id: String
    let keyLabel: String
    let title: String
    let keyCode: Int
    let action: () -> Void
}

/// Standard Commander Function Key Bar (F3–F8) conforming to classic dual-pane ergonomics.
public struct CommanderFunctionKeyBar: View {
    let palette: SparkleThemePalette
    let onView: () -> Void
    let onEdit: () -> Void
    let onCopy: () -> Void
    let onMove: () -> Void
    let onMkdir: () -> Void
    let onDelete: () -> Void

    public init(
        palette: SparkleThemePalette,
        onView: @escaping () -> Void,
        onEdit: @escaping () -> Void,
        onCopy: @escaping () -> Void,
        onMove: @escaping () -> Void,
        onMkdir: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.palette = palette
        self.onView = onView
        self.onEdit = onEdit
        self.onCopy = onCopy
        self.onMove = onMove
        self.onMkdir = onMkdir
        self.onDelete = onDelete
    }

    private var items: [FunctionKeyAction] {
        [
            FunctionKeyAction(id: "f3", keyLabel: "F3", title: "View", keyCode: NSF3FunctionKey, action: onView),
            FunctionKeyAction(id: "f4", keyLabel: "F4", title: "Edit", keyCode: NSF4FunctionKey, action: onEdit),
            FunctionKeyAction(id: "f5", keyLabel: "F5", title: "Copy", keyCode: NSF5FunctionKey, action: onCopy),
            FunctionKeyAction(id: "f6", keyLabel: "F6", title: "Move", keyCode: NSF6FunctionKey, action: onMove),
            FunctionKeyAction(id: "f7", keyLabel: "F7", title: "Mkdir", keyCode: NSF7FunctionKey, action: onMkdir),
            FunctionKeyAction(id: "f8", keyLabel: "F8", title: "Delete", keyCode: NSF8FunctionKey, action: onDelete)
        ]
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                functionButton(item)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background(palette.windowColor)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(palette.borderColor.opacity(0.4)),
            alignment: .top
        )
    }

    @ViewBuilder
    private func functionButton(_ item: FunctionKeyAction) -> some View {
        let baseButton = Button {
            item.action()
        } label: {
            HStack(spacing: 4) {
                Text(item.keyLabel)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.accentColor)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(palette.accentColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 3))

                Text(item.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.primaryTextColor)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 3)
            .background(palette.canvasColor.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(palette.borderColor.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)

        if let scalar = UnicodeScalar(item.keyCode) {
            baseButton.keyboardShortcut(KeyEquivalent(Character(scalar)), modifiers: [])
        } else {
            baseButton
        }
    }
}
