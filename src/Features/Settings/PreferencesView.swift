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
        TabView(selection: $selectedTab) {
            PreferencesLocalizationTab(appState: appState)
                .tag(SettingsTabIdentifier.general)
                .tabItem { Label(strings.t("prefs.tabGeneral"), systemImage: "globe") }

            PreferencesThemeTab(appState: appState)
                .tag(SettingsTabIdentifier.themes)
                .tabItem { Label(strings.t("prefs.tabThemes"), systemImage: SparkleTheme.Symbols.theme) }

            PreferencesTransfersTab(appState: appState)
                .tag(SettingsTabIdentifier.transfers)
                .tabItem { Label(strings.t("prefs.tabTransfers"), systemImage: "arrow.up.arrow.down.circle") }

            PreferencesTerminalTab(appState: appState)
                .tag(SettingsTabIdentifier.terminal)
                .tabItem { Label(strings.t("prefs.tabTerminal"), systemImage: "terminal") }

            PreferencesEditorTab(appState: appState)
                .tag(SettingsTabIdentifier.editor)
                .tabItem { Label(strings.t("prefs.tabEditor"), systemImage: "doc.text") }

            PreferencesSecurityTab(appState: appState)
                .tag(SettingsTabIdentifier.security)
                .tabItem { Label(strings.t("prefs.tabSecurity"), systemImage: "lock.shield") }

            PreferencesNetworkTab(appState: appState)
                .tag(SettingsTabIdentifier.network)
                .tabItem { Label(strings.t("prefs.tabNetwork"), systemImage: "network") }

            PreferencesSyncBookmarksTab(appState: appState)
                .tag(SettingsTabIdentifier.sync)
                .tabItem {
                    Label(strings.t("prefs.tabSyncBookmarks"), systemImage: "arrow.triangle.2.circlepath")
                }

            PreferencesArchivesTab(appState: appState)
                .tag(SettingsTabIdentifier.archives)
                .tabItem { Label(strings.t("prefs.tabArchives"), systemImage: "archivebox") }

            PreferencesUpdatesTab(appState: appState)
                .tag(SettingsTabIdentifier.updates)
                .tabItem { Label(strings.t("prefs.tabUpdates"), systemImage: SparkleTheme.Symbols.updates) }
        }
        .padding(SparkleTheme.Spacing.small)
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
