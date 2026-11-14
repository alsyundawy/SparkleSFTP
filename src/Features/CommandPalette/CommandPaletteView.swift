import AppKit
import SparkleCore
import SparkleDesignSystem
import SwiftUI

public struct CommandPaletteView: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var searchQuery: String = ""
    @State private var selectedIndex: Int = 0

    public init(appState: AppState) {
        self.appState = appState
    }

    private var strings: AppStrings {
        appState.strings
    }

    private var allItems: [CommandPaletteItem] {
        var items: [CommandPaletteItem] = []

        // Navigation actions
        items.append(CommandPaletteItem(
            id: "nav.preferences",
            title: strings.t("nav.settings"),
            subtitle: "Open Preferences window",
            category: .navigation,
            shortcutHint: "⌘,",
            action: { [weak appState] in appState?.openPreferencesWindow() }
        ))
        items.append(CommandPaletteItem(
            id: "nav.activityLog",
            title: strings.t("nav.activityLog"),
            subtitle: "View audit logs",
            category: .navigation,
            shortcutHint: "⌘L",
            action: { [weak appState] in appState?.isActivityLogVisible.toggle() }
        ))
        items.append(CommandPaletteItem(
            id: "nav.about",
            title: strings.t("nav.about"),
            subtitle: "About SparkleSFTP",
            category: .navigation,
            action: { [weak appState] in appState?.openAboutWindow() }
        ))

        // Connections
        for profile in appState.profiles {
            items.append(CommandPaletteItem(
                id: "conn.\(profile.id)",
                title: profile.name,
                subtitle: "\(profile.protocolType.rawValue)://\(profile.host):\(profile.port)",
                category: .connection,
                action: { [weak appState] in
                    Task { await appState?.connect(profile: profile) }
                }
            ))
        }

        return items
    }

    private var filteredItems: [CommandPaletteItem] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return allItems }
        return allItems.filter { item in
            item.title.lowercased().contains(query) || (item.subtitle?.lowercased().contains(query) ?? false)
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            resultsList
        }
        .frame(width: 560, height: 380)
        .sparkleWorkspaceSurface(appState.activePalette)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.35), radius: 16, x: 0, y: 8)
    }

    private var searchBar: some View {
        HStack(spacing: SparkleTheme.Spacing.small) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16))
                .foregroundStyle(appState.activePalette.secondaryTextColor)

            TextField(strings.t("palette.placeholder"), text: $searchQuery)
                .textFieldStyle(.plain)
                .font(SparkleTheme.Typography.title)
                .onSubmit {
                    executeFirstMatch()
                }

            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(appState.activePalette.secondaryTextColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(SparkleTheme.Spacing.medium)
        .background(appState.activePalette.canvasColor.opacity(0.6))
    }

    private var resultsList: some View {
        let items = filteredItems
        return Group {
            if items.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "questionmark.folder")
                        .font(.system(size: 32))
                        .foregroundStyle(appState.activePalette.secondaryTextColor)
                    Text(strings.t("palette.noResults"))
                        .font(SparkleTheme.Typography.caption)
                        .foregroundStyle(appState.activePalette.secondaryTextColor)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(items) { item in
                    rowItem(item)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            dismiss()
                            item.action()
                        }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
    }

    private func rowItem(_ item: CommandPaletteItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.category.systemImage)
                .font(.system(size: 13))
                .foregroundStyle(SparkleTheme.Colors.accent)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(SparkleTheme.Typography.body)
                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(SparkleTheme.Typography.caption)
                        .foregroundStyle(appState.activePalette.secondaryTextColor)
                }
            }

            Spacer()

            if let hint = item.shortcutHint {
                Text(hint)
                    .font(SparkleTheme.Typography.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(appState.activePalette.canvasColor)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(.vertical, 2)
    }

    private func executeFirstMatch() {
        guard let first = filteredItems.first else { return }
        dismiss()
        first.action()
    }
}
