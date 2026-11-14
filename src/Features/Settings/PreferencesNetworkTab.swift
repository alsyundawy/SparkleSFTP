import AppKit
import SparkleCore
import SparkleDesignSystem
import SwiftUI

struct PreferencesNetworkTab: View {
    @ObservedObject var appState: AppState

    private var strings: AppStrings {
        appState.strings
    }

    var body: some View {
        Form {
            Section(strings.t("prefs.network.connectionSection")) {
                Stepper(
                    "\(strings.t("prefs.network.keepAlive")): \(appState.extendedSettings.networkKeepAliveSeconds) s",
                    value: $appState.extendedSettings.networkKeepAliveSeconds,
                    in: 0 ... 300,
                    step: 5
                )

                Stepper(
                    "\(strings.t("prefs.network.timeout")): \(appState.extendedSettings.networkConnectTimeout) s",
                    value: $appState.extendedSettings.networkConnectTimeout,
                    in: 5 ... 120,
                    step: 5
                )

                Toggle(strings.t("prefs.network.ipv6"), isOn: $appState.extendedSettings.networkIpv6Preferred)
            }

            Section(strings.t("prefs.network.sshSection")) {
                Toggle(strings.t("prefs.network.sshAgent"), isOn: $appState.extendedSettings.networkSshAgentEnabled)

                TextField(
                    strings.t("prefs.network.subsystem"),
                    text: $appState.extendedSettings.networkSftpSubsystemPath
                )
                .textFieldStyle(.roundedBorder)
            }

            Section {
                Button(strings.t("prefs.resetTab")) {
                    appState.resetSettings(for: .network)
                }
            }
        }
        .padding(SparkleTheme.Spacing.small)
    }
}
