import SparkleCore
import SparkleDesignSystem
import SparkleSynchronization
import SwiftUI

public struct SyncPreviewSheet: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var exclusionsText = ".git, .DS_Store, node_modules"
    @State private var deleteExtras = false
    @State private var dryRunOnly = true
    @State private var confirmDestructive = false

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SparkleTheme.Spacing.medium) {
            HStack {
                Label(appState.strings.synchronize, systemImage: SparkleTheme.Symbols.sync)
                    .font(SparkleTheme.Typography.title)
                Spacer()
                Button(appState.strings.t("common.close")) { dismiss() }
            }

            VStack(alignment: .leading, spacing: SparkleTheme.Spacing.small) {
                HStack {
                    TextField(appState.strings.t("sync.exclusions"), text: $exclusionsText)
                        .textFieldStyle(.roundedBorder)
                    Picker(appState.strings.t("sync.direction"), selection: $appState.syncDirection) {
                        Text(appState.strings.t("sync.localToRemote")).tag(SyncDirection.localToRemote)
                        Text(appState.strings.t("sync.remoteToLocal")).tag(SyncDirection.remoteToLocal)
                        Text(appState.strings.t("sync.bidirectional")).tag(SyncDirection.bidirectional)
                    }
                    .frame(width: 210)
                }

                HStack {
                    Picker(appState.strings.t("sync.compareMode"), selection: $appState.syncComparisonMode) {
                        Text(appState.strings.t("sync.sizeAndTime")).tag(SyncComparisonMode.sizeAndMtime)
                        Text(appState.strings.t("sync.sizeOnly")).tag(SyncComparisonMode.sizeOnly)
                        Text(appState.strings.t("sync.sha256Strict")).tag(SyncComparisonMode.sha256Strict)
                    }
                    .frame(width: 170)
                    Toggle(appState.strings.t("sync.deleteExtras"), isOn: $deleteExtras)
                        .disabled(appState.syncDirection == .bidirectional)
                    Spacer()
                    Button(appState.strings.dryRunPreview) {
                        let patterns = exclusionsText
                            .split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        Task {
                            await appState.prepareSyncDryRun(
                                exclusions: patterns,
                                deleteExtras: appState.syncDirection == .bidirectional ? false : deleteExtras,
                                direction: appState.syncDirection,
                                mode: appState.syncComparisonMode
                            )
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            if let plan = appState.syncPlan {
                HStack {
                    StatusPill(
                        title: "\(appState.strings.t("sync.actionCreate")): \(plan.createActions.count)",
                        systemImage: "plus.circle",
                        tint: SparkleTheme.Colors.success
                    )
                    StatusPill(
                        title: "\(appState.strings.t("sync.actionUpdate")): \(plan.updateActions.count)",
                        systemImage: "arrow.triangle.2.circlepath",
                        tint: SparkleTheme.Colors.warning
                    )
                    StatusPill(
                        title: "\(appState.strings.t("sync.actionDelete")): \(plan.deleteActions.count)",
                        systemImage: "trash",
                        tint: SparkleTheme.Colors.danger
                    )
                    Spacer()
                    Text(
                        "\(appState.strings.t("sync.expires")): "
                            + "\(plan.expiresAt.formatted(date: .omitted, time: .standard))"
                    )
                    .font(SparkleTheme.Typography.caption)
                }

                List {
                    if !plan.createActions.isEmpty {
                        Section(appState.strings.t("sync.actionCreate")) {
                            ForEach(plan.createActions) { action in
                                actionRow(prefix: "+", action: action)
                            }
                        }
                    }
                    if !plan.updateActions.isEmpty {
                        Section(appState.strings.t("sync.actionUpdate")) {
                            ForEach(plan.updateActions) { action in
                                actionRow(prefix: "~", action: action)
                            }
                        }
                    }
                    if !plan.deleteActions.isEmpty {
                        Section(appState.strings.t("sync.actionDelete")) {
                            ForEach(plan.deleteActions) { action in
                                actionRow(prefix: "-", action: action)
                                    .foregroundStyle(SparkleTheme.Colors.danger)
                            }
                        }
                    }
                }
                .frame(minHeight: 200)

                Toggle(appState.strings.t("sync.dryRunOnly"), isOn: $dryRunOnly)
                if !dryRunOnly, !plan.deleteActions.isEmpty || !plan.updateActions.isEmpty {
                    Toggle(appState.strings.t("sync.confirmDestructive"), isOn: $confirmDestructive)
                        .foregroundStyle(SparkleTheme.Colors.danger)
                }

                HStack {
                    Spacer()
                    Button(appState.strings.executeSync) {
                        Task {
                            await appState.executeSyncPlan(dryRun: dryRunOnly)
                            dismiss()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        !dryRunOnly
                            && (!plan.deleteActions.isEmpty || !plan.updateActions.isEmpty)
                            && !confirmDestructive
                    )
                }
            } else {
                Text(appState.strings.t("sync.emptyPrompt"))
                    .font(SparkleTheme.Typography.caption)
                    .foregroundStyle(SparkleTheme.Colors.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 160)
            }
        }
        .padding(SparkleTheme.Spacing.large)
        .frame(width: 680)
    }

    private func actionRow(prefix: String, action: SyncAction) -> some View {
        let arrow = action.transferDirection == .upload ? "↑" : "↓"
        return Text("\(arrow) \(prefix) \(action.relativePath)")
            .font(SparkleTheme.Typography.monoSmall)
    }
}
