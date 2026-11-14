import AppKit
import SparkleCore
import SparkleDesignSystem
import SwiftUI

struct PreferencesTransfersTab: View {
    @ObservedObject var appState: AppState

    private var strings: AppStrings {
        appState.strings
    }

    var body: some View {
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

                Toggle(strings.t("prefs.transfers.autoPipeline"), isOn: $appState.extendedSettings.transferAutoPipeline)
                Toggle(strings.t("prefs.zlibCompression"), isOn: $appState.useZlibCompression)
            }

            Section(strings.t("prefs.transfers.bandwidthSection")) {
                let upSpeedText = speedString(appState.extendedSettings.transferSpeedLimitUpKBps)
                Stepper(
                    "\(strings.t("prefs.transfers.speedLimitUp")): \(upSpeedText)",
                    value: $appState.extendedSettings.transferSpeedLimitUpKBps,
                    in: 0 ... 100_000,
                    step: 256
                )

                let downSpeedText = speedString(appState.extendedSettings.transferSpeedLimitDownKBps)
                Stepper(
                    "\(strings.t("prefs.transfers.speedLimitDown")): \(downSpeedText)",
                    value: $appState.extendedSettings.transferSpeedLimitDownKBps,
                    in: 0 ... 100_000,
                    step: 256
                )
            }

            Section(strings.t("prefs.transfers.reliabilitySection")) {
                Stepper(
                    "\(strings.t("prefs.transfers.retryCount")): \(appState.extendedSettings.transferRetryCount)",
                    value: $appState.extendedSettings.transferRetryCount,
                    in: 0 ... 5
                )

                Toggle(
                    strings.t("prefs.transfers.preserveTimestamps"),
                    isOn: $appState.extendedSettings.transferPreserveTimestamps
                )
                Toggle(strings.t("prefs.transfers.useFilepart"), isOn: $appState.extendedSettings.transferUseFilepart)
                Toggle(
                    strings.t("prefs.transfers.verifySHA256"),
                    isOn: $appState.extendedSettings.transferVerifySHA256After
                )

                TextField(strings.t("prefs.transfers.rsyncPath"), text: $appState.extendedSettings.transferRsyncPath)
                    .textFieldStyle(.roundedBorder)
            }

            Section(strings.t("prefs.conflictPolicy")) {
                Picker(strings.t("prefs.uploadConflict"), selection: $appState.defaultUploadConflictPolicy) {
                    ForEach(TransferConflictPolicy.allCases, id: \.self) { policy in
                        Text(policy.localizedTitle(strings)).tag(policy)
                    }
                }

                Picker(strings.t("prefs.downloadConflict"), selection: $appState.defaultDownloadConflictPolicy) {
                    ForEach(TransferConflictPolicy.allCases, id: \.self) { policy in
                        Text(policy.localizedTitle(strings)).tag(policy)
                    }
                }
            }

            Section {
                Button(strings.t("prefs.resetTab")) {
                    appState.resetSettings(for: .transfers)
                }
            }
        }
        .padding(SparkleTheme.Spacing.small)
    }

    private func speedString(_ kbps: Int) -> String {
        kbps == 0 ? strings.t("prefs.transfers.unlimited") : "\(kbps) KB/s"
    }
}
