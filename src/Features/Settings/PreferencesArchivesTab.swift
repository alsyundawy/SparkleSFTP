import AppKit
import SparkleCore
import SparkleDesignSystem
import SwiftUI

struct PreferencesArchivesTab: View {
    @ObservedObject var appState: AppState

    private var strings: AppStrings {
        appState.strings
    }

    var body: some View {
        Form {
            Section(strings.t("prefs.archives.formatSection")) {
                Picker(
                    strings.t("prefs.archives.defaultFormat"),
                    selection: $appState.extendedSettings.archiveDefaultFormat
                ) {
                    Text("ZIP (.zip)").tag("ZIP")
                    Text("7-Zip (.7z)").tag("7Z")
                    Text("Tar GZip (.tar.gz)").tag("TAR.GZ")
                    Text("Tar XZ (.tar.xz)").tag("TAR.XZ")
                }

                let compLevel = appState.extendedSettings.archiveCompressionLevel
                Stepper(
                    "\(strings.t("prefs.archives.compressionLevel")): \(compLevel)",
                    value: $appState.extendedSettings.archiveCompressionLevel,
                    in: 0 ... 9,
                    step: 1
                )
            }

            Section(strings.t("prefs.archives.toolchainSection")) {
                LabeledContent(
                    "bsdtar",
                    value: FileManager.default.fileExists(atPath: "/usr/bin/tar") ? "Available" : "Missing"
                )
                LabeledContent(
                    "zip / unzip",
                    value: FileManager.default.fileExists(atPath: "/usr/bin/zip") ? "Available" : "Missing"
                )
                let has7zz = FileManager.default.fileExists(atPath: "/usr/local/bin/7zz")
                LabeledContent(
                    "7zz (Homebrew)",
                    value: has7zz ? "Available" : "Not Found (Optional)"
                )
            }

            Section {
                Button(strings.t("prefs.resetTab")) {
                    appState.resetSettings(for: .archives)
                }
            }
        }
        .padding(SparkleTheme.Spacing.small)
    }
}
