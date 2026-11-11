import SparkleDesignSystem
import SparkleTerminal
import SwiftUI

/// Recursive split-pane renderer for standalone iTerm2-style terminal tabs.
struct StandaloneTerminalSplitView: View {
    let node: TerminalSplitNode
    let focusedPaneID: UUID
    let totalPanes: Int
    @ObservedObject var manager: StandaloneTerminalManager
    let palette: SparkleThemePalette
    let strings: AppStrings
    let terminalColors: TerminalThemeColors

    var body: some View {
        switch node {
        case let .pane(paneID):
            paneView(for: paneID)
        case let .split(_, axis, _, first, second):
            splitContainer(axis: axis, first: first, second: second)
        }
    }

    @ViewBuilder
    private func splitContainer(
        axis: TerminalSplitAxis,
        first: TerminalSplitNode,
        second: TerminalSplitNode
    ) -> some View {
        switch axis {
        case .verticalDivider:
            HSplitView {
                StandaloneTerminalSplitView(
                    node: first,
                    focusedPaneID: focusedPaneID,
                    totalPanes: totalPanes,
                    manager: manager,
                    palette: palette,
                    strings: strings,
                    terminalColors: terminalColors
                )
                .frame(minWidth: 180, maxWidth: .infinity, maxHeight: .infinity)

                StandaloneTerminalSplitView(
                    node: second,
                    focusedPaneID: focusedPaneID,
                    totalPanes: totalPanes,
                    manager: manager,
                    palette: palette,
                    strings: strings,
                    terminalColors: terminalColors
                )
                .frame(minWidth: 180, maxWidth: .infinity, maxHeight: .infinity)
            }
        case .horizontalDivider:
            VSplitView {
                StandaloneTerminalSplitView(
                    node: first,
                    focusedPaneID: focusedPaneID,
                    totalPanes: totalPanes,
                    manager: manager,
                    palette: palette,
                    strings: strings,
                    terminalColors: terminalColors
                )
                .frame(maxWidth: .infinity, minHeight: 120, maxHeight: .infinity)

                StandaloneTerminalSplitView(
                    node: second,
                    focusedPaneID: focusedPaneID,
                    totalPanes: totalPanes,
                    manager: manager,
                    palette: palette,
                    strings: strings,
                    terminalColors: terminalColors
                )
                .frame(maxWidth: .infinity, minHeight: 120, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private func paneView(for paneID: UUID) -> some View {
        if let pane = manager.panes[paneID] {
            let isFocused = focusedPaneID == paneID
            VStack(spacing: 0) {
                if totalPanes > 1 || pane.hasExited {
                    paneHeaderBar(pane: pane, isFocused: isFocused)
                }
                LocalTerminalProcessRepresentable(
                    pane: pane,
                    manager: manager,
                    themeColors: terminalColors
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .simultaneousGesture(
                    TapGesture().onEnded {
                        manager.focusPane(pane.id)
                    }
                )
            }
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(
                        isFocused && totalPanes > 1 ? palette.accentColor : Color.clear,
                        lineWidth: isFocused && totalPanes > 1 ? 1.5 : 0
                    )
            )
        } else {
            Spacer()
        }
    }

    private func paneHeaderBar(pane: StandaloneTerminalPane, isFocused: Bool) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(pane.hasExited ? SparkleTheme.Colors.danger : palette.accentColor)
                .frame(width: 7, height: 7)
            Text(pane.title)
                .font(SparkleTheme.Typography.caption.weight(isFocused ? .semibold : .regular))
                .foregroundStyle(palette.primaryTextColor)
                .lineLimit(1)
            Text(abbreviatedPath(pane.currentDirectory))
                .font(SparkleTheme.Typography.monoSmall)
                .foregroundStyle(palette.secondaryTextColor)
                .lineLimit(1)
                .truncationMode(.head)
            if pane.hasExited {
                let code = pane.exitCode.map { "\($0)" } ?? "0"
                Text("\(strings.t("terminal.standalone.exited")) (\(code))")
                    .font(.caption2)
                    .foregroundStyle(SparkleTheme.Colors.warning)
            }
            Spacer()
            Button {
                manager.closePane(id: pane.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
            }
            .buttonStyle(.borderless)
            .help(strings.t("terminal.standalone.closePane"))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(palette.windowColor.opacity(0.9))
    }

    private func abbreviatedPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home {
            return "~"
        }
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
