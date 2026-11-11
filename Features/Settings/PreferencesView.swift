import SparkleCore
import SparkleDesignSystem
import SwiftUI

public struct PreferencesView: View {
    @ObservedObject var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        Form {
            Section("Appearance & Localization") {
                Picker("Language / Bahasa", selection: $appState.language) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Transfer Engine & Conflicts") {
                Stepper(
                    "Max Simultaneous Transfers: \(appState.maxGlobalConcurrentTransfers)",
                    value: $appState.maxGlobalConcurrentTransfers,
                    in: 1 ... 8
                )
                .onChange(of: appState.maxGlobalConcurrentTransfers) { _ in
                    Task { await appState.applyTransferConcurrencySettings() }
                }
                Stepper(
                    "Max Per-Host Connections: \(appState.maxPerHostConcurrentTransfers)",
                    value: $appState.maxPerHostConcurrentTransfers,
                    in: 1 ... 4
                )
                .onChange(of: appState.maxPerHostConcurrentTransfers) { _ in
                    Task { await appState.applyTransferConcurrencySettings() }
                }
                Picker("Default Conflict Action", selection: $appState.defaultConflictPolicy) {
                    Text("Ask Every Time").tag(TransferConflictPolicy.ask)
                    Text("Overwrite").tag(TransferConflictPolicy.overwrite)
                    Text("Auto-Rename").tag(TransferConflictPolicy.rename)
                    Text("Skip").tag(TransferConflictPolicy.skip)
                }
                .onChange(of: appState.defaultConflictPolicy) { _ in
                    Task { await appState.applyConflictPolicySettings() }
                }
            }

            Section("Updates (Sparkle Ed25519)") {
                Button("Check for Updates...") {
                    appState.checkForUpdates()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 440, height: 300)
    }
}
