import SparkleCore
import SparkleDesignSystem
import SparkleSecurity
import SwiftUI
import UniformTypeIdentifiers

public struct ConnectionManagerView: View {
    @ObservedObject var appState: AppState
    @Binding var editorMode: ConnectionEditorMode?
    @State private var isShowingImporter = false
    @State private var isAddingGroup = false
    @State private var newGroupName = ""
    @State private var pendingDeleteIDs: Set<UUID> = []
    @State private var isConfirmingBatchDelete = false

    public init(
        appState: AppState,
        editorMode: Binding<ConnectionEditorMode?>
    ) {
        self.appState = appState
        _editorMode = editorMode
    }

    public var body: some View {
        let palette = appState.activePalette
        VStack(spacing: 0) {
            searchBar(palette: palette)
            visibleActionBar(palette: palette)

            ConnectionListTableView(
                rows: Self.buildTableRows(
                    filteredProfiles: appState.filteredProfiles,
                    recentProfiles: appState.recentProfiles,
                    groups: appState.groups,
                    searchText: appState.searchText,
                    strings: appState.strings
                ),
                selectedIDs: $appState.selectedProfileIDs,
                strings: appState.strings,
                palette: palette,
                onConnect: { profile in Task { await appState.connect(profile: profile) } },
                onConnectInNewTab: { profile in
                    Task { await appState.connect(profile: profile, openInNewTab: true) }
                },
                onConnectInNewWindow: { profile in appState.openProfileInNewWindow(profile.id) },
                onOpenExternalTerminal: { profile in Task { await appState.openInExternalTerminal(profile) } },
                onNewConnection: { editorMode = .create },
                onNewGroup: { isAddingGroup = true },
                onSelectAll: { appState.selectAllVisibleProfiles() },
                onEdit: { profile in editorMode = .edit(profile) },
                onClone: { profile in Task { _ = await appState.cloneProfile(profile) } },
                onRequestDelete: { ids in requestDelete(ids: ids) },
                onDeleteGroup: { groupID in Task { await appState.deleteGroup(id: groupID) } },
                onExportRequested: { selectedOnly in appState.openExportSheet(selectedOnly: selectedOnly) },
                onImportRequested: { appState.isShowingImportSheet = true }
            )

            bottomControls(palette: palette)
        }
        .background(palette.windowColor, ignoresSafeAreaEdges: [])
        .foregroundStyle(palette.primaryTextColor)
        .tint(palette.accentColor)
        .alert(appState.strings.t("nav.newGroupTitle"), isPresented: $isAddingGroup) {
            TextField(appState.strings.t("nav.groupName"), text: $newGroupName)
            Button(appState.strings.t("common.cancel"), role: .cancel) { newGroupName = "" }
            Button(appState.strings.t("common.create")) {
                let name = newGroupName
                newGroupName = ""
                Task { await appState.createGroup(named: name) }
            }
        }
        .alert(appState.strings.t("conn.confirmDeleteTitle"), isPresented: $isConfirmingBatchDelete) {
            Button(appState.strings.t("common.cancel"), role: .cancel) { pendingDeleteIDs = [] }
            Button(appState.strings.t("common.delete"), role: .destructive) {
                let ids = pendingDeleteIDs
                pendingDeleteIDs = []
                Task { await appState.deleteProfiles(ids: ids) }
            }
        } message: {
            Text("\(appState.strings.t("conn.confirmDeleteMessage")) (\(pendingDeleteIDs.count))")
        }
        .fileImporter(
            isPresented: $isShowingImporter,
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
}

private extension ConnectionManagerView {
    func searchBar(palette: SparkleThemePalette) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(palette.secondaryTextColor)
            TextField(appState.strings.connectionsTitle, text: $appState.searchText)
                .textFieldStyle(.plain)
            if !appState.searchText.isEmpty {
                Button {
                    appState.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(palette.secondaryTextColor)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(palette.canvasColor)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(palette.borderColor, lineWidth: 1))
        .padding(SparkleTheme.Spacing.small)
    }

    func visibleActionBar(palette: SparkleThemePalette) -> some View {
        HStack(spacing: 6) {
            Button {
                if let primary = appState.primarySelectedProfile {
                    Task { await appState.connect(profile: primary) }
                }
            } label: {
                Label(appState.strings.connect, systemImage: SparkleTheme.Symbols.connect)
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(appState.primarySelectedProfile == nil)
            .help(appState.strings.connect)

            Button {
                editorMode = .create
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(appState.strings.newConnection)

            Button {
                if let primary = appState.primarySelectedProfile {
                    editorMode = .edit(primary)
                }
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(appState.primarySelectedProfile == nil)
            .help(appState.strings.t("common.edit"))

            selectionActionButtons
        }
        .padding(.horizontal, SparkleTheme.Spacing.small)
        .padding(.bottom, SparkleTheme.Spacing.tiny)
        .background(palette.windowColor, ignoresSafeAreaEdges: [])
    }

    @ViewBuilder
    private var selectionActionButtons: some View {
        Button {
            appState.selectAllVisibleProfiles()
        } label: {
            Label(appState.strings.t("conn.selectAllShort"), systemImage: "checklist")
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(appState.filteredProfiles.isEmpty)
        .help(appState.strings.t("conn.selectAll"))

        Button(role: .destructive) {
            requestDelete(ids: appState.selectedProfileIDs)
        } label: {
            Image(systemName: "trash")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(appState.selectedProfileIDs.isEmpty)
        .help(appState.strings.t("conn.deleteSelected"))
    }

    func bottomControls(palette: SparkleThemePalette) -> some View {
        VStack(spacing: 6) {
            if !appState.selectedProfileIDs.isEmpty {
                HStack {
                    Text("\(appState.selectedProfileIDs.count) \(appState.strings.t("transfers.items"))")
                        .font(SparkleTheme.Typography.caption)
                        .foregroundStyle(palette.secondaryTextColor)
                    Spacer()
                    Button(appState.strings.t("conn.clearSelection")) {
                        appState.selectedProfileIDs.removeAll()
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)

                    Button(appState.strings.t("conn.deleteSelected"), role: .destructive) {
                        requestDelete(ids: appState.selectedProfileIDs)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            HStack(spacing: SparkleTheme.Spacing.tiny) {
                Button(appState.strings.t("nav.newGroup")) {
                    isAddingGroup = true
                }
                .controlSize(.small)

                Button(appState.strings.t("conn.cloneShort")) {
                    if let primary = appState.primarySelectedProfile {
                        Task { _ = await appState.cloneProfile(primary) }
                    }
                }
                .controlSize(.small)
                .disabled(appState.primarySelectedProfile == nil)

                Spacer(minLength: 4)

                importExportMenus()
            }
        }
        .padding(SparkleTheme.Spacing.small)
        .frame(maxWidth: .infinity)
        .background(palette.windowColor, ignoresSafeAreaEdges: [])
        .overlay(alignment: .top) {
            palette.borderColor.frame(height: 1)
        }
    }

    private func importExportMenus() -> some View {
        HStack(spacing: SparkleTheme.Spacing.tiny) {
            Menu(appState.strings.t("nav.importMenu")) {
                Button(appState.strings.t("nav.importSSHConfig")) {
                    Task { await appState.importFromSSHConfig() }
                }
                Button(appState.strings.t("nav.importExternal")) {
                    appState.isShowingImportSheet = true
                }
            }
            .controlSize(.small)

            Menu(appState.strings.t("nav.exportMenu")) {
                Button(appState.strings.t("nav.exportAll")) {
                    appState.openExportSheet(selectedOnly: false)
                }
                Button(appState.strings.t("nav.exportSelected")) {
                    appState.openExportSheet(selectedOnly: true)
                }
                .disabled(appState.primarySelectedProfile == nil)
            }
            .controlSize(.small)
        }
    }

    func requestDelete(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        pendingDeleteIDs = ids
        isConfirmingBatchDelete = true
    }
}

extension ConnectionManagerView {
    nonisolated static func buildTableRows(
        filteredProfiles: [ConnectionProfile],
        recentProfiles: [ConnectionProfile],
        groups: [ServerGroup],
        searchText: String,
        strings: AppStrings
    ) -> [ConnectionTableRowItem] {
        let profilesByGroup = Dictionary(grouping: filteredProfiles) { $0.groupID }
        let validGroupIDs = Set(groups.map(\.id))
        var rows: [ConnectionTableRowItem] = []

        if searchText.isEmpty, !recentProfiles.isEmpty {
            rows.append(.section(id: "sec-recent", title: strings.t("nav.recent"), groupID: nil))
            for profile in recentProfiles.prefix(4) {
                rows.append(.profile(profile, rowKey: "recent-\(profile.id.uuidString)"))
            }
        }

        for group in groups {
            let members = profilesByGroup[group.id] ?? []
            if !members.isEmpty || searchText.isEmpty {
                rows.append(.section(id: "sec-\(group.id.uuidString)", title: group.name, groupID: group.id))
                for profile in members {
                    rows.append(.profile(profile, rowKey: "grp-\(group.id.uuidString)-\(profile.id.uuidString)"))
                }
            }
        }

        let ungrouped = filteredProfiles.filter { profile in
            guard let groupID = profile.groupID else { return true }
            return !validGroupIDs.contains(groupID)
        }
        rows.append(.section(id: "sec-connections", title: strings.connectionsTitle, groupID: nil))
        for profile in ungrouped {
            rows.append(.profile(profile, rowKey: "main-\(profile.id.uuidString)"))
        }
        return rows
    }
}
