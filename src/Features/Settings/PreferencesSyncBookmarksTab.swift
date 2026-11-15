import AppKit
import SparkleCore
import SparkleDesignSystem
import SwiftUI

struct PreferencesSyncBookmarksTab: View {
    @ObservedObject var appState: AppState

    private var strings: AppStrings {
        appState.strings
    }

    var body: some View {
        ScrollView {
            Form {
                syncSection
                bookmarksSection
                resetSection
            }
            .padding(.horizontal, SparkleTheme.Spacing.medium)
            .padding(.vertical, SparkleTheme.Spacing.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var syncSection: some View {
        Section(strings.t("prefs.sync.syncSection")) {
            Picker(strings.t("prefs.sync.mode"), selection: $appState.extendedSettings.syncDefaultMode) {
                Text(strings.t("prefs.sync.modeSizeMtime")).tag("sizeAndMtime")
                Text(strings.t("prefs.sync.modeSha256")).tag("sha256Strict")
            }

            TextField(strings.t("prefs.sync.exclusions"), text: $appState.extendedSettings.syncDefaultExclusions)
                .textFieldStyle(.roundedBorder)

            Toggle(strings.t("prefs.sync.watchEnabled"), isOn: $appState.extendedSettings.syncWatchEnabled)

            Picker(strings.t("prefs.sync.watchDelete"), selection: $appState.extendedSettings.syncWatchDeleteMode) {
                Text(strings.t("prefs.sync.deleteOff")).tag("off")
                Text(strings.t("prefs.sync.deleteAsk")).tag("ask")
                Text(strings.t("prefs.sync.deleteSync")).tag("sync")
            }
        }
    }

    private var bookmarksSection: some View {
        Section(strings.t("prefs.sync.bookmarksSection")) {
            Stepper(
                "\(strings.t("prefs.sync.historySize")): \(appState.extendedSettings.bookmarksHistorySize)",
                value: $appState.extendedSettings.bookmarksHistorySize,
                in: 5 ... 100,
                step: 5
            )

            Toggle(
                strings.t("prefs.sync.syncBrowsing"),
                isOn: $appState.extendedSettings.bookmarksSyncBrowsingDefault
            )
        }
    }

    private var resetSection: some View {
        Section {
            Button(strings.t("prefs.resetTab")) {
                appState.resetSettings(for: .sync)
            }
        }
    }
}
