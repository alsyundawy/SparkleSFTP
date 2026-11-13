import SparkleCore
import SparkleDesignSystem
import SparklePersistence
import SwiftUI
import UniformTypeIdentifiers

/// Dedicated preview and selective importer for FileZilla XML, WinSCP INI, and native SparkleSFTP connection files.
public struct ImportConnectionsSheet: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIndices: Set<Int> = []
    @State private var createFoldersAsGroups = true
    @State private var skipDuplicates = true
    @State private var isPickingFile = false
    @State private var archivePassphrase = ""

    public init(appState: AppState) {
        self.appState = appState
    }

    private var strings: AppStrings {
        appState.strings
    }

    private var report: ExternalImportReport? {
        appState.pendingImportReport
    }

    private var formatBadgeTitle: String {
        guard let report else { return "" }
        switch report.format {
        case .fileZillaXML: return strings.t("import.fileZillaFormat")
        case .commanderINI: return strings.t("import.iniFormat")
        case .nativeJSON: return strings.t("import.nativeJSONFormat")
        case .encryptedArchive: return strings.t("import.encryptedArchiveFormat")
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SparkleTheme.Spacing.medium) {
            HStack {
                Label(strings.t("import.title"), systemImage: "square.and.arrow.down.on.square")
                    .font(SparkleTheme.Typography.title)
                Spacer()
                Button(strings.t("common.close")) {
                    appState.pendingImportReport = nil
                    dismiss()
                }
            }

            HStack(spacing: SparkleTheme.Spacing.small) {
                Button(strings.t("import.chooseFile")) {
                    isPickingFile = true
                }
                .buttonStyle(.borderedProminent)

                let detectedSites = ExternalConnectionFileReader.defaultFileZillaSiteFiles()
                if let firstSite = detectedSites.first {
                    Button(strings.t("import.autoDetectFileZilla")) {
                        appState.inspectExternalConnections(from: firstSite)
                    }
                }

                Spacer()
                if report != nil {
                    StatusPill(
                        title: formatBadgeTitle,
                        systemImage: "doc.text",
                        tint: SparkleTheme.Colors.accent
                    )
                }
            }

            if let report, report.format == .encryptedArchive {
                encryptedUnlockView
            } else if let report, !report.connections.isEmpty {
                Toggle(strings.t("import.createFoldersAsGroups"), isOn: $createFoldersAsGroups)
                Toggle(strings.t("import.skipDuplicates"), isOn: $skipDuplicates)

                HStack {
                    Button(strings.t("import.selectAll")) {
                        selectedIndices = Set(report.connections.indices)
                    }
                    Button(strings.t("import.deselectAll")) {
                        selectedIndices = []
                    }
                    Spacer()
                    Text("\(selectedIndices.count) / \(report.connections.count)")
                        .font(SparkleTheme.Typography.caption)
                }

                List(Array(report.connections.enumerated()), id: \.offset) { idx, entry in
                    entryRow(index: idx, entry: entry)
                        .listRowBackground(appState.activePalette.canvasColor)
                }
                .scrollContentBackground(.hidden)
                .background(appState.activePalette.canvasColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text(strings.t("import.noEntries"))
                    .font(SparkleTheme.Typography.body)
                    .foregroundStyle(appState.activePalette.secondaryTextColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            HStack {
                Spacer()
                Button(strings.t("common.cancel"), role: .cancel) {
                    appState.pendingImportReport = nil
                    dismiss()
                }
                if report?.format != .encryptedArchive {
                    Button("\(strings.t("import.importSelected")) (\(selectedIndices.count))") {
                        commitSelected()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedIndices.isEmpty)
                }
            }
        }
        .padding(SparkleTheme.Spacing.large)
        .frame(width: 680, height: 520)
        .sparkleWorkspaceSurface(appState.activePalette)
        .onAppear {
            selectAllCurrent()
        }
        .onChange(of: report) { _ in
            selectAllCurrent()
        }
        .fileImporter(
            isPresented: $isPickingFile,
            allowedContentTypes: [
                UTType(filenameExtension: "sparklesftp") ?? .data,
                .json,
                .xml,
                .plainText,
                UTType(filenameExtension: "ini") ?? .data,
                .data
            ],
            allowsMultipleSelection: false
        ) { result in
            if case let .success(urls) = result, let url = urls.first {
                appState.inspectExternalConnections(from: url)
            }
        }
    }

    private var encryptedUnlockView: some View {
        VStack(spacing: SparkleTheme.Spacing.medium) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 42))
                .foregroundStyle(SparkleTheme.Colors.accent)

            Text(strings.t("import.encryptedArchiveTitle"))
                .font(SparkleTheme.Typography.headline)

            Text(strings.t("import.encryptedArchiveSubtitle"))
                .font(SparkleTheme.Typography.caption)
                .foregroundStyle(appState.activePalette.secondaryTextColor)
                .multilineTextAlignment(.center)

            HStack(spacing: 8) {
                SecureField(strings.t("import.archivePassphrasePlaceholder"), text: $archivePassphrase)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 300)

                Button(strings.t("import.unlockArchive")) {
                    appState.unlockEncryptedImport(passphrase: archivePassphrase)
                }
                .buttonStyle(.borderedProminent)
                .disabled(archivePassphrase.isEmpty)
            }

            if let err = appState.archivePassphraseError {
                Text(err)
                    .font(SparkleTheme.Typography.caption)
                    .foregroundStyle(SparkleTheme.Colors.danger)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(SparkleTheme.Spacing.large)
        .background(appState.activePalette.canvasColor)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func commitSelected() {
        guard let report else { return }
        let chosen = report.connections.enumerated()
            .filter { selectedIndices.contains($0.offset) }
            .map(\.element)
        Task {
            await appState.commitImportedConnections(
                chosen,
                createGroups: createFoldersAsGroups,
                skipDuplicates: skipDuplicates
            )
            appState.pendingImportReport = nil
            dismiss()
        }
    }

    private func entryRow(index: Int, entry: ImportedConnection) -> some View {
        let isChecked = Binding<Bool>(
            get: { selectedIndices.contains(index) },
            set: { checked in
                if checked {
                    selectedIndices.insert(index)
                } else {
                    selectedIndices.remove(index)
                }
            }
        )
        return HStack {
            Toggle(isOn: isChecked) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(entry.profile.name).font(SparkleTheme.Typography.headline)
                        Text(entry.profile.protocolType.displayName)
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(SparkleTheme.Colors.accent.opacity(0.15))
                            .clipShape(Capsule())
                        if let group = entry.groupName {
                            Text(group)
                                .font(.caption2)
                                .foregroundStyle(SparkleTheme.Colors.secondaryText)
                        }
                    }
                    Text("\(entry.profile.username)@\(entry.profile.host):\(entry.profile.port)")
                        .font(SparkleTheme.Typography.monoSmall)
                        .foregroundStyle(SparkleTheme.Colors.secondaryText)
                }
            }
            Spacer()
            secretStatusBadge(entry.secretStatus)
        }
    }

    @ViewBuilder
    private func secretStatusBadge(_ status: ImportedSecretStatus) -> some View {
        switch status {
        case .plaintextReady:
            StatusPill(
                title: strings.t("import.secretReady"),
                systemImage: "key.fill",
                tint: SparkleTheme.Colors.success
            )
        case .encryptedUnavailable:
            StatusPill(
                title: strings.t("import.encryptedSecret"),
                systemImage: "exclamationmark.triangle.fill",
                tint: SparkleTheme.Colors.warning
            )
        case .none:
            Text(strings.t("import.noSecret"))
                .font(SparkleTheme.Typography.caption)
                .foregroundStyle(SparkleTheme.Colors.secondaryText)
        }
    }

    private func selectAllCurrent() {
        if let report, report.format != .encryptedArchive {
            selectedIndices = Set(report.connections.indices)
        } else {
            selectedIndices = []
        }
    }
}
