import AppKit
import SparkleCore
import SparkleDesignSystem
import SwiftUI

public struct PreferencesView: View {
    @ObservedObject var appState: AppState
    @State private var selectedTab: SettingsTabIdentifier = .general
    @State private var searchQuery: String = ""
    @State private var showResetAllConfirmation = false
    @State private var exportErrorMessage: String?

    public init(appState: AppState) {
        self.appState = appState
    }

    private var strings: AppStrings {
        appState.strings
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            if searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                tabContentView
            } else {
                searchResultsView
            }
        }
        .frame(
            minWidth: 740,
            idealWidth: 760,
            maxWidth: .infinity,
            minHeight: 580,
            idealHeight: 600,
            maxHeight: .infinity
        )
        .sparkleWorkspaceSurface(appState.activePalette)
        .background(SparkleWindowConfigurator(palette: appState.activePalette, allowFullScreen: true))
        .onReceive(NotificationCenter.default.publisher(for: .sparklePreferencesDidChange)) { notification in
            if (notification.object as? UUID) != appState.windowInstanceID {
                appState.reloadPreferencesFromNotification()
            }
        }
        .alert(isPresented: $showResetAllConfirmation) {
            Alert(
                title: Text(strings.t("prefs.resetAllTitle")),
                message: Text(strings.t("prefs.resetAllConfirm")),
                primaryButton: .destructive(Text(strings.t("prefs.resetAllButton"))) {
                    appState.resetAllSettingsToDefaults()
                },
                secondaryButton: .cancel()
            )
        }
    }

    private var headerBar: some View {
        HStack(spacing: SparkleTheme.Spacing.small) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(appState.activePalette.secondaryTextColor)
            TextField(strings.t("prefs.searchPlaceholder"), text: $searchQuery)
                .textFieldStyle(.plain)
                .frame(maxWidth: 240)

            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(appState.activePalette.secondaryTextColor)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Button(strings.t("prefs.exportSettings")) {
                exportSettingsToFile()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button(strings.t("prefs.importSettings")) {
                importSettingsFromFile()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button(strings.t("prefs.resetAll")) {
                showResetAllConfirmation = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, SparkleTheme.Spacing.medium)
        .padding(.vertical, SparkleTheme.Spacing.small)
        .background(appState.activePalette.canvasColor.opacity(0.5))
    }

    private var tabContentView: some View {
        VStack(spacing: 0) {
            fixedTwoRowTabBar
            Divider()
            activeTabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(SparkleTheme.Spacing.small)
        }
    }

    private var fixedTwoRowTabBar: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                tabButton(tab: .general, title: strings.t("prefs.tabGeneral"), icon: "globe")
                tabButton(tab: .themes, title: strings.t("prefs.tabThemes"), icon: SparkleTheme.Symbols.theme)
                tabButton(tab: .transfers, title: strings.t("prefs.tabTransfers"), icon: "arrow.up.arrow.down.circle")
                tabButton(tab: .terminal, title: strings.t("prefs.tabTerminal"), icon: "terminal")
                tabButton(tab: .editor, title: strings.t("prefs.tabEditor"), icon: "doc.text")
            }
            HStack(spacing: 6) {
                tabButton(tab: .security, title: strings.t("prefs.tabSecurity"), icon: "lock.shield")
                tabButton(tab: .network, title: strings.t("prefs.tabNetwork"), icon: "network")
                tabButton(tab: .sync, title: strings.t("prefs.tabSyncBookmarks"), icon: "arrow.triangle.2.circlepath")
                tabButton(tab: .archives, title: strings.t("prefs.tabArchives"), icon: "archivebox")
                tabButton(tab: .updates, title: strings.t("prefs.tabUpdates"), icon: SparkleTheme.Symbols.updates)
            }
        }
        .padding(.horizontal, SparkleTheme.Spacing.medium)
        .padding(.vertical, SparkleTheme.Spacing.small)
        .background(appState.activePalette.canvasColor.opacity(0.6))
    }

    private func tabButton(tab: SettingsTabIdentifier, title: String, icon: String) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            selectedTab = tab
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: isSelected ? .bold : .regular))
                Text(title)
                    .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? SparkleTheme.Colors.accent.opacity(0.18) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? SparkleTheme.Colors.accent.opacity(0.6) : Color.clear, lineWidth: 1)
            )
            .foregroundStyle(isSelected ? SparkleTheme.Colors.accent : appState.activePalette.primaryTextColor)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var activeTabContent: some View {
        switch selectedTab {
        case .general:
            PreferencesLocalizationTab(appState: appState)
        case .themes:
            PreferencesThemeTab(appState: appState)
        case .transfers:
            PreferencesTransfersTab(appState: appState)
        case .terminal:
            PreferencesTerminalTab(appState: appState)
        case .editor:
            PreferencesEditorTab(appState: appState)
        case .security:
            PreferencesSecurityTab(appState: appState)
        case .network:
            PreferencesNetworkTab(appState: appState)
        case .sync:
            PreferencesSyncBookmarksTab(appState: appState)
        case .archives:
            PreferencesArchivesTab(appState: appState)
        case .updates:
            PreferencesUpdatesTab(appState: appState)
        }
    }

    private var searchResultsView: some View {
        let results = SettingsRegistry.search(query: searchQuery)
        return VStack(alignment: .leading, spacing: SparkleTheme.Spacing.small) {
            Text("\(results.count) \(strings.t("prefs.searchResultsCount"))")
                .font(SparkleTheme.Typography.caption)
                .foregroundStyle(appState.activePalette.secondaryTextColor)
                .padding(.horizontal, SparkleTheme.Spacing.medium)
                .padding(.top, SparkleTheme.Spacing.small)

            List {
                ForEach(results, id: \.id) { descriptor in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(descriptor.key)
                                .font(.system(.caption, design: .monospaced))
                                .bold()
                            Spacer()
                            Text(strings.t(descriptor.tab.titleKey))
                                .font(SparkleTheme.Typography.caption)
                                .foregroundStyle(SparkleTheme.Colors.accent)
                        }
                        Text(strings.t(descriptor.titleKey))
                            .font(SparkleTheme.Typography.body)
                        Text(strings.t(descriptor.descriptionKey))
                            .font(SparkleTheme.Typography.caption)
                            .foregroundStyle(appState.activePalette.secondaryTextColor)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedTab = descriptor.tab
                        searchQuery = ""
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    private func exportSettingsToFile() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "SparkleSFTP-Settings.json"
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            let dict = appState.exportSettingsDictionary()
            if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    private func importSettingsFromFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url,
           let data = try? Data(contentsOf: url),
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            appState.importSettingsDictionary(dict)
        }
    }
}
