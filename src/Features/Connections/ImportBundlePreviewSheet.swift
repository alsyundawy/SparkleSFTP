import AppKit
import SparkleCore
import SparkleDesignSystem
import SparklePersistence
import SwiftUI

public struct ImportBundlePreviewSheet: View {
    @ObservedObject var appState: AppState
    let bundle: SparkleConfigBundle
    @Environment(\.dismiss) private var dismiss

    @State private var conflictPolicy: ConfigImportConflictPolicy = .skipExisting
    @State private var importSettings: Bool = true
    @State private var importBookmarks: Bool = true
    @State private var isExecuting = false
    @State private var resultMessage: String?
    @State private var errorMessage: String?

    public init(appState: AppState, bundle: SparkleConfigBundle) {
        self.appState = appState
        self.bundle = bundle
    }

    private var strings: AppStrings {
        appState.strings
    }

    private var plan: ConfigImportPlan {
        ConfigImporter.buildImportPlan(
            bundle: bundle,
            existingProfiles: appState.profiles,
            existingGroups: appState.groups
        )
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SparkleTheme.Spacing.medium) {
            headerView
            bundleSummaryView
            policySection
            profilesDiffView

            if let resultMessage {
                Text(resultMessage)
                    .font(SparkleTheme.Typography.caption)
                    .foregroundStyle(SparkleTheme.Colors.success)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(SparkleTheme.Typography.caption)
                    .foregroundStyle(SparkleTheme.Colors.danger)
            }

            Spacer(minLength: 0)
            footerActionView
        }
        .padding(SparkleTheme.Spacing.large)
        .frame(width: 620, height: 560)
        .sparkleWorkspaceSurface(appState.activePalette)
    }

    private var headerView: some View {
        HStack {
            Label(strings.t("import.bundleTitle"), systemImage: "shippingbox.fill")
                .font(SparkleTheme.Typography.title)
            Spacer()
            Button(strings.t("common.close")) {
                dismiss()
            }
        }
    }

    private var bundleSummaryView: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Version: \(bundle.appVersion)")
                    .font(SparkleTheme.Typography.caption)
                Text("Profiles: \(bundle.payload.profiles.count)")
                    .font(SparkleTheme.Typography.caption)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Bookmarks: \(bundle.payload.bookmarks.count)")
                    .font(SparkleTheme.Typography.caption)
                Text("History: \(bundle.payload.pathHistory.count)")
                    .font(SparkleTheme.Typography.caption)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Snippets: \(bundle.payload.snippets.count)")
                    .font(SparkleTheme.Typography.caption)
                Text("Settings: \(bundle.payload.settings.count) keys")
                    .font(SparkleTheme.Typography.caption)
            }
            Spacer()
        }
        .padding(SparkleTheme.Spacing.small)
        .background(appState.activePalette.canvasColor)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var policySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(strings.t("import.conflictPolicyTitle"))
                .font(SparkleTheme.Typography.headline)

            Picker("", selection: $conflictPolicy) {
                Text(strings.t("import.policySkip")).tag(ConfigImportConflictPolicy.skipExisting)
                Text(strings.t("import.policyOverwrite")).tag(ConfigImportConflictPolicy.overwrite)
                Text(strings.t("import.policyRename")).tag(ConfigImportConflictPolicy.keepBoth)
                Text(strings.t("import.policyMerge")).tag(ConfigImportConflictPolicy.mergeGroups)
            }
            .pickerStyle(.segmented)

            HStack {
                Toggle("Import Settings", isOn: $importSettings)
                    .disabled(bundle.payload.settings.isEmpty)
                Spacer()
                Toggle("Import Bookmarks", isOn: $importBookmarks)
                    .disabled(bundle.payload.bookmarks.isEmpty)
            }
            .font(SparkleTheme.Typography.caption)
        }
    }

    private var profilesDiffView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Profiles Diff (\(plan.newProfiles.count) new, \(plan.conflictingProfiles.count) conflicts)")
                .font(SparkleTheme.Typography.caption)
                .foregroundStyle(appState.activePalette.secondaryTextColor)

            List {
                Section("New Profiles (\(plan.newProfiles.count))") {
                    ForEach(plan.newProfiles, id: \.id) { profile in
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(SparkleTheme.Colors.success)
                            Text(profile.name)
                            Spacer()
                            Text("\(profile.protocolType.rawValue)://\(profile.host)")
                                .font(SparkleTheme.Typography.caption)
                                .foregroundStyle(appState.activePalette.secondaryTextColor)
                        }
                    }
                }
                if !plan.conflictingProfiles.isEmpty {
                    Section("Conflicting Profiles (\(plan.conflictingProfiles.count))") {
                        ForEach(plan.conflictingProfiles.indices, id: \.self) { idx in
                            let item = plan.conflictingProfiles[idx]
                            HStack {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundStyle(SparkleTheme.Colors.warning)
                                Text(item.imported.name)
                                Spacer()
                                Text(conflictPolicy.rawValue)
                                    .font(SparkleTheme.Typography.caption)
                                    .foregroundStyle(SparkleTheme.Colors.warning)
                            }
                        }
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .frame(maxHeight: 200)
        }
    }

    private var footerActionView: some View {
        HStack {
            Spacer()
            Button(strings.t("common.cancel"), role: .cancel) {
                dismiss()
            }

            Button(strings.t("import.executeButton")) {
                executeImport()
            }
            .buttonStyle(.borderedProminent)
            .disabled(isExecuting)
        }
    }

    private func executeImport() {
        isExecuting = true
        errorMessage = nil
        let policy = conflictPolicy
        let currentPlan = plan
        let bundleCopy = bundle
        let shouldImportSettings = importSettings

        Task {
            do {
                let result = try await ConfigImporter.applyPlan(
                    plan: currentPlan,
                    policy: policy,
                    connectionStore: appState.connectionStore
                )

                if shouldImportSettings, !bundleCopy.payload.settings.isEmpty {
                    await MainActor.run {
                        appState.importSettingsDictionary(bundleCopy.payload.settings)
                    }
                }

                let loadedProfiles = try await appState.connectionStore.loadProfiles()
                let loadedGroups = try await appState.connectionStore.loadGroups()

                await MainActor.run {
                    appState.profiles = loadedProfiles
                    appState.groups = loadedGroups
                    let inCount = result.importedProfileCount
                    let skipCount = result.skippedProfileCount
                    let summary = "Imported \(inCount) profiles, \(skipCount) skipped"
                    appState.statusBannerMessage = summary
                    isExecuting = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isExecuting = false
                }
            }
        }
    }
}
