import SparkleCore
import SparkleDesignSystem
import SparklePersistence
import SwiftUI
import UniformTypeIdentifiers

/// Dedicated preview and selective importer for FileZilla XML and Commander INI connection files.
public struct ImportConnectionsSheet: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIndices: Set<Int> = []
    @State private var createFoldersAsGroups = true
    @State private var skipDuplicates = true
    @State private var isPickingFile = false

    public init(appState: AppState) {
        self.appState = appState
    }

    private var strings: AppStrings {
        appState.strings
    }

    private var report: ExternalImportReport? {
        appState.pendingImportReport
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
                if let report {
                    let formatLabel = report.format == .fileZillaXML
                        ? strings.t("import.fileZillaFormat")
                        : strings.t("import.iniFormat")
                    StatusPill(title: formatLabel, systemImage: "doc.text", tint: SparkleTheme.Colors.accent)
                }
            }

            if let report, !report.connections.isEmpty {
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
                Button("\(strings.t("import.importSelected")) (\(selectedIndices.count))") {
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
                .buttonStyle(.borderedProminent)
                .disabled(selectedIndices.isEmpty)
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
        if let report {
            selectedIndices = Set(report.connections.indices)
        } else {
            selectedIndices = []
        }
    }
}
