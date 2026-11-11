import SparkleCore
import SparkleDesignSystem
import SwiftUI

public struct PreferencesView: View {
    @ObservedObject var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    private var strings: AppStrings {
        appState.strings
    }

    public var body: some View {
        TabView {
            PreferencesLocalizationTab(appState: appState)
                .tabItem {
                    Label(strings.t("prefs.tabGeneral"), systemImage: "globe")
                }

            PreferencesThemeTab(appState: appState)
                .tabItem {
                    Label(strings.t("prefs.tabThemes"), systemImage: SparkleTheme.Symbols.theme)
                }

            transfersAndBehaviorTab
                .tabItem {
                    Label(strings.t("prefs.tabTransfers"), systemImage: "arrow.up.arrow.down.circle")
                }

            PreferencesUpdatesTab(appState: appState)
                .tabItem {
                    Label(strings.t("prefs.tabUpdates"), systemImage: SparkleTheme.Symbols.updates)
                }
        }
        .padding(SparkleTheme.Spacing.medium)
        .frame(
            minWidth: 640,
            idealWidth: 720,
            maxWidth: .infinity,
            minHeight: 480,
            idealHeight: 560,
            maxHeight: .infinity
        )
        .sparkleWorkspaceSurface(appState.activePalette)
        .background(SparkleWindowConfigurator(palette: appState.activePalette, allowFullScreen: false))
        .onReceive(NotificationCenter.default.publisher(for: .sparklePreferencesDidChange)) { notification in
            if (notification.object as? UUID) != appState.windowInstanceID {
                appState.reloadPreferencesFromNotification()
            }
        }
    }

    private var transfersAndBehaviorTab: some View {
        Form {
            Section(strings.t("prefs.doubleClick")) {
                Picker(strings.t("prefs.doubleClick"), selection: $appState.openDoubleClickInInternalEditor) {
                    Text(strings.t("prefs.doubleClickInternal")).tag(true)
                    Text(strings.t("prefs.doubleClickQuickLook")).tag(false)
                }
            }

            Section(strings.t("prefs.tabTransfers")) {
                Stepper(
                    "\(strings.t("prefs.maxGlobal")): \(appState.maxGlobalConcurrentTransfers)",
                    value: $appState.maxGlobalConcurrentTransfers,
                    in: 1 ... 16
                )
                .onChange(of: appState.maxGlobalConcurrentTransfers) { _ in
                    Task { await appState.applyTransferConcurrencySettings() }
                }

                Stepper(
                    "\(strings.t("prefs.maxPerHost")): \(appState.maxPerHostConcurrentTransfers)",
                    value: $appState.maxPerHostConcurrentTransfers,
                    in: 1 ... 8
                )
                .onChange(of: appState.maxPerHostConcurrentTransfers) { _ in
                    Task { await appState.applyTransferConcurrencySettings() }
                }

                Stepper(
                    "\(strings.t("prefs.pipelineDepth")): \(appState.transferPipelineDepth)",
                    value: $appState.transferPipelineDepth,
                    in: 1 ... 16
                )
                .onChange(of: appState.transferPipelineDepth) { _ in
                    Task { await appState.applyTransferConcurrencySettings() }
                }

                Toggle(strings.t("prefs.zlibCompression"), isOn: $appState.useZlibCompression)

                Picker(strings.t("prefs.defaultConflict"), selection: $appState.defaultConflictPolicy) {
                    Text(strings.t("prefs.conflictAsk")).tag(TransferConflictPolicy.ask)
                    Text(strings.t("prefs.conflictOverwrite")).tag(TransferConflictPolicy.overwrite)
                    Text(strings.t("prefs.conflictOverwriteIfNewer")).tag(TransferConflictPolicy.overwriteIfNewer)
                    Text(strings.t("prefs.conflictOverwriteIfDiffSize"))
                        .tag(TransferConflictPolicy.overwriteIfDifferentSize)
                    Text(strings.t("prefs.conflictOverwriteIfDiffOrNewer"))
                        .tag(TransferConflictPolicy.overwriteIfDifferentSizeOrNewer)
                    Text(strings.t("prefs.conflictResume")).tag(TransferConflictPolicy.resume)
                    Text(strings.t("prefs.conflictRename")).tag(TransferConflictPolicy.rename)
                    Text(strings.t("prefs.conflictSkip")).tag(TransferConflictPolicy.skip)
                }
                .onChange(of: appState.defaultConflictPolicy) { _ in
                    Task { await appState.applyConflictPolicySettings() }
                }
            }

            Section(strings.t("prefs.terminalAndLibs")) {
                Picker(strings.t("prefs.externalTerminal"), selection: $appState.externalTerminalApp) {
                    ForEach(ExternalTerminalApp.allCases, id: \.self) { app in
                        Text(app.displayName).tag(app)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(appState.activePalette.windowColor)
    }
}
