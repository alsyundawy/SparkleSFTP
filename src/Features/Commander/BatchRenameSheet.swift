import AppKit
import SparkleCore
import SparkleDesignSystem
import SparkleFileManager
import SwiftUI

public struct BatchRenameSheet: View {
    @ObservedObject var appState: AppState
    let filenames: [String]
    let existingNames: Set<String>
    let onCommit: @Sendable ([RenamePreviewItem]) async -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var rule = BatchRenameRule()
    @State private var isExecuting = false

    public init(
        appState: AppState,
        filenames: [String],
        existingNames: Set<String> = [],
        onCommit: @escaping @Sendable ([RenamePreviewItem]) async -> Void
    ) {
        self.appState = appState
        self.filenames = filenames
        self.existingNames = existingNames
        self.onCommit = onCommit
    }

    private var strings: AppStrings {
        appState.strings
    }

    private var previewItems: [RenamePreviewItem] {
        BatchRenamePlanner.plan(filenames: filenames, rule: rule, existingNames: existingNames)
    }

    private var allValid: Bool {
        !previewItems.isEmpty && previewItems.allSatisfy(\.isValid)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SparkleTheme.Spacing.medium) {
            headerView
            controlsView
            previewListView
            footerActionView
        }
        .padding(SparkleTheme.Spacing.large)
        .frame(width: 640, height: 560)
        .sparkleWorkspaceSurface(appState.activePalette)
    }

    private var headerView: some View {
        HStack {
            Label(strings.t("rename.batchTitle"), systemImage: "pencil.and.outline")
                .font(SparkleTheme.Typography.title)
            Spacer()
            Button(strings.t("common.close")) {
                dismiss()
            }
        }
    }

    private var controlsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField(strings.t("rename.find"), text: $rule.findText)
                    .textFieldStyle(.roundedBorder)
                TextField(strings.t("rename.replace"), text: $rule.replaceText)
                    .textFieldStyle(.roundedBorder)
                Toggle(strings.t("rename.useRegex"), isOn: $rule.useRegex)
                    .toggleStyle(.checkbox)
            }

            HStack(spacing: 8) {
                TextField(strings.t("rename.prefix"), text: $rule.prefix)
                    .textFieldStyle(.roundedBorder)
                TextField(strings.t("rename.suffix"), text: $rule.suffix)
                    .textFieldStyle(.roundedBorder)

                Picker(strings.t("rename.case"), selection: $rule.caseTransform) {
                    Text(strings.t("rename.caseUnchanged")).tag(RenameCaseTransform.unchanged)
                    Text(strings.t("rename.caseLower")).tag(RenameCaseTransform.lowercase)
                    Text(strings.t("rename.caseUpper")).tag(RenameCaseTransform.uppercase)
                    Text(strings.t("rename.caseCapitalized")).tag(RenameCaseTransform.capitalized)
                }
                .frame(width: 150)
            }

            HStack(spacing: 12) {
                Stepper(
                    "\(strings.t("rename.counterStart")): \(rule.counterStart)",
                    value: $rule.counterStart,
                    in: 0 ... 1000
                )
                Stepper(
                    "\(strings.t("rename.padding")): \(rule.counterPadding)",
                    value: $rule.counterPadding,
                    in: 1 ... 6
                )
                Spacer()
                Text("[C] = Counter")
                    .font(SparkleTheme.Typography.caption)
                    .foregroundStyle(appState.activePalette.secondaryTextColor)
            }
        }
        .padding(SparkleTheme.Spacing.small)
        .background(appState.activePalette.canvasColor)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var previewListView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(previewItems.count) items")
                .font(SparkleTheme.Typography.caption)
                .foregroundStyle(appState.activePalette.secondaryTextColor)

            List(previewItems) { item in
                HStack {
                    Text(item.originalName)
                        .foregroundStyle(appState.activePalette.secondaryTextColor)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10))
                        .foregroundStyle(appState.activePalette.secondaryTextColor)
                    Text(item.proposedName)
                        .bold()

                    Spacer()
                    if item.isValid {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(SparkleTheme.Colors.success)
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(SparkleTheme.Colors.danger)
                            Text(item.errorReason ?? "Invalid")
                                .font(SparkleTheme.Typography.caption)
                                .foregroundStyle(SparkleTheme.Colors.danger)
                        }
                    }
                }
                .font(SparkleTheme.Typography.body)
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    private var footerActionView: some View {
        HStack {
            Spacer()
            Button(strings.t("common.cancel"), role: .cancel) {
                dismiss()
            }

            Button("\(strings.t("rename.actionButton")) (\(previewItems.count))") {
                executeBatchRename()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!allValid || isExecuting)
        }
    }

    private func executeBatchRename() {
        isExecuting = true
        let items = previewItems
        Task {
            await onCommit(items)
            await MainActor.run {
                isExecuting = false
                dismiss()
            }
        }
    }
}
