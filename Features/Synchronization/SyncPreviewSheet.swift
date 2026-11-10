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
                Button("Close") { dismiss() }
            }

            HStack {
                TextField("Exclusions (comma-separated)", text: $exclusionsText)
                    .textFieldStyle(.roundedBorder)
                Toggle("Delete Remote Extras", isOn: $deleteExtras)
                Button(appState.strings.dryRunPreview) {
                    let patterns = exclusionsText
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    Task { await appState.prepareSyncDryRun(exclusions: patterns, deleteExtras: deleteExtras) }
                }
                .buttonStyle(.borderedProminent)
            }

            if let plan = appState.syncPlan {
                HStack {
                    StatusPill(
                        title: "Create: \(plan.createActions.count)",
                        systemImage: "plus.circle",
                        tint: SparkleTheme.Colors.success
                    )
                    StatusPill(
                        title: "Update: \(plan.updateActions.count)",
                        systemImage: "arrow.triangle.2.circlepath",
                        tint: SparkleTheme.Colors.warning
                    )
                    StatusPill(
                        title: "Delete: \(plan.deleteActions.count)",
                        systemImage: "trash",
                        tint: SparkleTheme.Colors.danger
                    )
                    Spacer()
                    Text("Expires: \(plan.expiresAt.formatted(date: .omitted, time: .standard))")
                        .font(SparkleTheme.Typography.caption)
                }

                List {
                    if !plan.createActions.isEmpty {
                        Section("Create") {
                            ForEach(plan.createActions) { action in
                                Text("+ \(action.relativePath)").font(SparkleTheme.Typography.monoSmall)
                            }
                        }
                    }
                    if !plan.updateActions.isEmpty {
                        Section("Update") {
                            ForEach(plan.updateActions) { action in
                                Text("~ \(action.relativePath)").font(SparkleTheme.Typography.monoSmall)
                            }
                        }
                    }
                    if !plan.deleteActions.isEmpty {
                        Section("Delete") {
                            ForEach(plan.deleteActions) { action in
                                Text("- \(action.relativePath)")
                                    .font(SparkleTheme.Typography.monoSmall)
                                    .foregroundStyle(SparkleTheme.Colors.danger)
                            }
                        }
                    }
                }
                .frame(minHeight: 200)

                Toggle("Dry-Run Only (No Mutations)", isOn: $dryRunOnly)
                if !dryRunOnly && (!plan.deleteActions.isEmpty || !plan.updateActions.isEmpty) {
                    Toggle("Confirm destructive updates/deletes against revalidated targets", isOn: $confirmDestructive)
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
                Text("Click Dry-Run Preview to compare Local and Remote folders safely.")
                    .font(SparkleTheme.Typography.caption)
                    .foregroundStyle(SparkleTheme.Colors.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 160)
            }
        }
        .padding(SparkleTheme.Spacing.large)
        .frame(width: 620)
    }
}
