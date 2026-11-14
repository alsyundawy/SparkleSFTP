import AppKit
import SparkleCore
import SparkleDesignSystem
import SwiftUI

struct PreferencesEditorTab: View {
    @ObservedObject var appState: AppState

    private var strings: AppStrings {
        appState.strings
    }

    var body: some View {
        Form {
            Section(strings.t("prefs.editor.externalSection")) {
                HStack {
                    TextField(
                        strings.t("prefs.editor.externalApp"),
                        text: $appState.extendedSettings.editorExternalAppPath
                    )
                    .textFieldStyle(.roundedBorder)

                    Button(strings.t("common.choose")) {
                        chooseExternalEditor()
                    }
                }

                Toggle(
                    strings.t("prefs.editor.autoUpload"),
                    isOn: $appState.extendedSettings.editorAutoUploadOnSave
                )
                Toggle(
                    strings.t("prefs.editor.remoteChange"),
                    isOn: $appState.extendedSettings.editorRemoteChangeDetection
                )
            }

            Section(strings.t("prefs.editor.formattingSection")) {
                Stepper(
                    "\(strings.t("prefs.editor.tabWidth")): \(appState.extendedSettings.editorTabWidth) spaces",
                    value: $appState.extendedSettings.editorTabWidth,
                    in: 2 ... 8,
                    step: 2
                )

                Toggle(strings.t("prefs.editor.autoSave"), isOn: $appState.extendedSettings.editorAutoSave)
            }

            Section {
                Button(strings.t("prefs.resetTab")) {
                    appState.resetSettings(for: .editor)
                }
            }
        }
        .padding(SparkleTheme.Spacing.small)
    }

    private func chooseExternalEditor() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK, let selectedURL = panel.url {
            appState.editorExternalAppPath = selectedURL.path
        }
    }
}
