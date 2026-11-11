import SparkleDesignSystem
import SparkleTerminal
import SwiftUI

/// Collapsible iTerm2-style tab strip for `StandaloneTerminalWindowView`.
struct StandaloneTerminalTabStrip: View {
    @ObservedObject var manager: StandaloneTerminalManager
    let palette: SparkleThemePalette
    let strings: AppStrings

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(manager.tabs) { tab in
                    tabChip(for: tab)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
        }
        .background(palette.windowColor)
    }

    private func tabChip(for tab: StandaloneTerminalTab) -> some View {
        let isSelected = tab.id == (manager.activeTab?.id)
        return HStack(spacing: 6) {
            Image(systemName: "terminal")
                .font(.caption)
                .foregroundStyle(isSelected ? palette.accentColor : palette.secondaryTextColor)
            Text(tab.title)
                .font(SparkleTheme.Typography.caption.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(palette.primaryTextColor)
                .lineLimit(1)
            if manager.tabs.count > 1 {
                Button {
                    manager.closeTab(id: tab.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(palette.secondaryTextColor)
                }
                .buttonStyle(.plain)
                .help(strings.t("tabs.closeTab"))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? palette.canvasColor : palette.windowColor.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    isSelected ? palette.accentColor.opacity(0.75) : palette.borderColor,
                    lineWidth: 1
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            manager.selectedTabID = tab.id
        }
    }
}

/// Inline find bar wired to `SwiftTerm.TerminalView` search APIs.
struct StandaloneTerminalSearchBar: View {
    @ObservedObject var manager: StandaloneTerminalManager
    let palette: SparkleThemePalette
    let strings: AppStrings

    var body: some View {
        HStack(spacing: 8) {
            TextField(strings.t("editor.findPlaceholder"), text: $manager.searchQuery)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 180, maxWidth: 280)
                .onSubmit {
                    manager.findNext()
                }
            Toggle(strings.t("editor.matchCase"), isOn: $manager.searchCaseSensitive)
                .toggleStyle(.button)
            Toggle(strings.t("editor.regex"), isOn: $manager.searchRegex)
                .toggleStyle(.button)
            Toggle(strings.t("terminal.standalone.wholeWord"), isOn: $manager.searchWholeWord)
                .toggleStyle(.button)
            Button(strings.t("editor.findPrev")) {
                manager.findPrevious()
            }
            .buttonStyle(.bordered)
            Button(strings.t("editor.findNext")) {
                manager.findNext()
            }
            .buttonStyle(.bordered)
            if !manager.searchMatchSummaryText.isEmpty {
                Text(manager.searchMatchSummaryText)
                    .font(SparkleTheme.Typography.monoSmall)
                    .foregroundStyle(palette.secondaryTextColor)
            }
            Spacer()
            Button {
                manager.toggleSearchBar()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(palette.windowColor.opacity(0.95))
    }
}
