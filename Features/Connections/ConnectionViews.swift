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
                onOpenExternalTerminal: { profile in Task { await appState.openInExternalTerminal(profile) } },
                onEdit: { profile in editorMode = .edit(profile) },
                onClone: { profile in Task { _ = await appState.cloneProfile(profile) } },
                onRequestDelete: { ids in requestDelete(ids: ids) },
                onDeleteGroup: { groupID in Task { await appState.deleteGroup(id: groupID) } }
            )

            bottomControls(palette: palette)
        }
        .background(palette.windowColor)
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

    private func searchBar(palette: SparkleThemePalette) -> some View {
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

    private func bottomControls(palette: SparkleThemePalette) -> some View {
        VStack(spacing: 6) {
            if appState.selectedProfileIDs.count > 1 {
                HStack {
                    Text("\(appState.selectedProfileIDs.count) \(appState.strings.t("transfers.items"))")
                        .font(SparkleTheme.Typography.caption)
                        .foregroundStyle(palette.secondaryTextColor)
                    Spacer()
                    Button(appState.strings.t("conn.deleteSelected"), role: .destructive) {
                        requestDelete(ids: appState.selectedProfileIDs)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            HStack(spacing: SparkleTheme.Spacing.tiny) {
                Button {
                    editorMode = .create
                } label: {
                    Label(appState.strings.newConnection, systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)

                Button(appState.strings.t("nav.newGroup")) {
                    isAddingGroup = true
                }

                Menu(appState.strings.t("nav.importMenu")) {
                    Button(appState.strings.t("nav.importSSHConfig")) {
                        Task { await appState.importFromSSHConfig() }
                    }
                    Button(appState.strings.t("nav.importExternal")) {
                        appState.isShowingImportSheet = true
                    }
                }

                connectionActionsMenu
            }
        }
        .padding(SparkleTheme.Spacing.small)
        .frame(maxWidth: .infinity)
        .background(palette.windowColor)
        .overlay(alignment: .top) {
            palette.borderColor.frame(height: 1)
        }
    }

    private var connectionActionsMenu: some View {
        Menu {
            Button(appState.strings.t("conn.selectAll")) {
                appState.selectAllVisibleProfiles()
            }
            .disabled(appState.filteredProfiles.isEmpty)

            if let primary = appState.primarySelectedProfile {
                Button(appState.strings.t("common.edit")) {
                    editorMode = .edit(primary)
                }
                Button(appState.strings.t("conn.cloneConnection")) {
                    Task { _ = await appState.cloneProfile(primary) }
                }
            }

            Divider()

            Button(appState.strings.t("conn.deleteSelected"), role: .destructive) {
                requestDelete(ids: appState.selectedProfileIDs)
            }
            .disabled(appState.selectedProfileIDs.isEmpty)
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .frame(width: 24)
    }

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

    private func requestDelete(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        pendingDeleteIDs = ids
        isConfirmingBatchDelete = true
    }
}
