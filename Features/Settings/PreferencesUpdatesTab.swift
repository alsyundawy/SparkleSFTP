import AppKit
import SparkleCore
import SparkleDesignSystem
import SparkleSecurity
import SwiftUI

struct PreferencesUpdatesTab: View {
    @ObservedObject var appState: AppState

    private var strings: AppStrings {
        appState.strings
    }

    private var isFeedValid: Bool {
        UpdateConfigurationValidator.isValidHTTPSFeed(appState.autoUpdateSettings.customFeedURL)
    }

    var body: some View {
        Form {
            Section(strings.t("prefs.tabUpdates")) {
                LabeledContent(strings.t("prefs.currentVersion"), value: "v\(appState.installedAppVersion)")

                StatusPill(
                    title: appState.isSignedUpdatesReady
                        ? strings.t("prefs.signedMode")
                        : strings.t("prefs.communityMode"),
                    systemImage: appState.isSignedUpdatesReady ? "checkmark.shield.fill" : "shield.lefthalf.filled",
                    tint: appState.isSignedUpdatesReady ? SparkleTheme.Colors.success : SparkleTheme.Colors.accent
                )

                Toggle(strings.t("prefs.autoCheck"), isOn: $appState.autoUpdateSettings.automaticallyChecks)
                    .onChange(of: appState.autoUpdateSettings.automaticallyChecks) { _ in
                        appState.applyAutoUpdateConfiguration()
                    }

                Toggle(strings.t("prefs.autoDownload"), isOn: $appState.autoUpdateSettings.automaticallyDownloads)
                    .disabled(!appState.isSignedUpdatesReady)
                    .onChange(of: appState.autoUpdateSettings.automaticallyDownloads) { _ in
                        appState.applyAutoUpdateConfiguration()
                    }

                Picker(strings.t("prefs.checkFrequency"), selection: $appState.autoUpdateSettings.checkFrequency) {
                    Text(strings.t("prefs.freqHourly")).tag(UpdateCheckFrequency.hourly)
                    Text(strings.t("prefs.freqDaily")).tag(UpdateCheckFrequency.daily)
                    Text(strings.t("prefs.freqWeekly")).tag(UpdateCheckFrequency.weekly)
                    Text(strings.t("prefs.freqManual")).tag(UpdateCheckFrequency.manual)
                }
                .onChange(of: appState.autoUpdateSettings.checkFrequency) { _ in
                    appState.applyAutoUpdateConfiguration()
                }

                Picker(strings.t("prefs.channel"), selection: $appState.autoUpdateSettings.channel) {
                    Text(strings.t("prefs.channelStable")).tag(AutoUpdateChannel.stable)
                    Text(strings.t("prefs.channelBeta")).tag(AutoUpdateChannel.beta)
                }
                .onChange(of: appState.autoUpdateSettings.channel) { _ in
                    appState.applyAutoUpdateConfiguration()
                }
            }

            Section(strings.t("prefs.feedURL")) {
                TextField(strings.t("prefs.feedURL"), text: $appState.autoUpdateSettings.customFeedURL)
                    .textFieldStyle(.roundedBorder)
                    .font(SparkleTheme.Typography.monoSmall)

                if !isFeedValid {
                    Text(strings.t("prefs.invalidFeed"))
                        .font(SparkleTheme.Typography.caption)
                        .foregroundStyle(SparkleTheme.Colors.danger)
                }

                HStack {
                    Button(strings.t("prefs.resetFeed")) {
                        appState.resetAutoUpdateFeedURL()
                    }
                    Spacer()
                    let checkedLabel = appState.autoUpdateSettings.lastCheckedAt?
                        .formatted(date: .abbreviated, time: .shortened) ?? strings.t("prefs.never")
                    Text("\(strings.t("prefs.lastChecked")): \(checkedLabel)")
                        .font(SparkleTheme.Typography.caption)
                        .foregroundStyle(SparkleTheme.Colors.secondaryText)
                }

                checkActionsRow
            }
        }
        .formStyle(.grouped)
    }

    private var checkActionsRow: some View {
        HStack {
            Button(strings.t("prefs.checkNow")) {
                Task { await appState.checkForUpdates(manual: true) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isFeedValid || appState.autoUpdateStatus == .checking)

            Spacer()

            switch appState.autoUpdateStatus {
            case .idle:
                EmptyView()
            case .checking:
                ProgressView().controlSize(.small)
                Text(strings.t("prefs.checking"))
                    .font(SparkleTheme.Typography.caption)
            case let .upToDate(version):
                Text("\(strings.t("prefs.upToDate")) (v\(version))")
                    .font(SparkleTheme.Typography.caption)
                    .foregroundStyle(SparkleTheme.Colors.success)
            case let .updateAvailable(version, releaseURL, _):
                Text("\(strings.t("prefs.updateAvailable")): v\(version)")
                    .font(SparkleTheme.Typography.caption)
                    .foregroundStyle(SparkleTheme.Colors.accent)
                Button(strings.t("prefs.openReleasePage")) {
                    NSWorkspace.shared.open(releaseURL)
                }
            case .sparkleNativeTriggered:
                Text(strings.t("prefs.signedMode"))
                    .font(SparkleTheme.Typography.caption)
                    .foregroundStyle(SparkleTheme.Colors.success)
            case let .failed(reason):
                Text(reason)
                    .font(SparkleTheme.Typography.caption)
                    .foregroundStyle(SparkleTheme.Colors.danger)
            }
        }
    }
}
