import AppKit
import SparkleCore
import SparkleDesignSystem
import SwiftUI

struct PreferencesTerminalTab: View {
    @ObservedObject var appState: AppState

    private var strings: AppStrings {
        appState.strings
    }

    var body: some View {
        Form {
            Section(strings.t("prefs.terminal.typography")) {
                TextField(strings.t("prefs.terminal.fontName"), text: $appState.extendedSettings.terminalFontName)
                    .textFieldStyle(.roundedBorder)

                Stepper(
                    "\(strings.t("prefs.terminal.fontSize")): \(Int(appState.extendedSettings.terminalFontSize)) pt",
                    value: $appState.extendedSettings.terminalFontSize,
                    in: 9.0 ... 36.0,
                    step: 1.0
                )

                Stepper(
                    "\(strings.t("prefs.terminal.scrollback")): \(appState.extendedSettings.terminalScrollbackLines)",
                    value: $appState.extendedSettings.terminalScrollbackLines,
                    in: 500 ... 100_000,
                    step: 500
                )
            }

            Section(strings.t("prefs.terminal.behavior")) {
                Picker(strings.t("prefs.terminal.bellMode"), selection: $appState.extendedSettings.terminalBellMode) {
                    Text(strings.t("prefs.terminal.bellAudible")).tag("audible")
                    Text(strings.t("prefs.terminal.bellVisual")).tag("visual")
                    Text(strings.t("prefs.terminal.bellOff")).tag("off")
                }

                Toggle(strings.t("prefs.terminal.osc7Sync"), isOn: $appState.extendedSettings.terminalOsc7SyncEnabled)

                Picker(
                    strings.t("prefs.terminal.osc52Policy"),
                    selection: $appState.extendedSettings.terminalOsc52Policy
                ) {
                    Text(strings.t("prefs.terminal.osc52Off")).tag("off")
                    Text(strings.t("prefs.terminal.osc52Read")).tag("read")
                    Text(strings.t("prefs.terminal.osc52Write")).tag("write")
                    Text(strings.t("prefs.terminal.osc52ReadWrite")).tag("readwrite")
                }

                TextField(
                    strings.t("prefs.terminal.shellPath"),
                    text: $appState.extendedSettings.terminalLocalShellPath
                )
                .textFieldStyle(.roundedBorder)

                Picker(strings.t("prefs.externalTerminal"), selection: $appState.externalTerminalApp) {
                    ForEach(ExternalTerminalApp.allCases, id: \.self) { app in
                        Text(app.displayName).tag(app)
                    }
                }
            }

            Section {
                Button(strings.t("prefs.resetTab")) {
                    appState.resetSettings(for: .terminal)
                }
            }
        }
        .padding(SparkleTheme.Spacing.small)
    }
}
