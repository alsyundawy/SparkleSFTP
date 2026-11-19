import AppKit
import SwiftUI

/// Modal close button that decouples visible glyph presentation from the invisible
/// key equivalent receiver, eliminating the macOS blue focus ring artifact across sheets and dialogs.
public struct ModalCloseButton: View {
    let action: () -> Void
    @State private var isHovering = false

    public init(action: @escaping () -> Void) {
        self.action = action
    }

    public var body: some View {
        ZStack {
            // Invisible zero-size key equivalent handler capturing Escape
            Button(action: action) {
                EmptyView()
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)

            // Visible clean button without focus rings
            Button(action: action) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(isHovering ? Color.secondary : Color.secondary.opacity(0.7))
            }
            .buttonStyle(.plain)
            .disableFocusEffectIfAvailable()
            .onHover { isHovering = $0 }
            .help("Close (Esc)")
            .accessibilityLabel("Close")
        }
    }
}

private extension View {
    @ViewBuilder
    func disableFocusEffectIfAvailable() -> some View {
        if #available(macOS 14.0, *) {
            self.focusEffectDisabled()
        } else {
            self
        }
    }
}
