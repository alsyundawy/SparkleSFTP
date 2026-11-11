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
        let filtered = appState.filteredProfiles
        let profilesByGroup = Dictionary(grouping: filtered) { $0.groupID }
        let validGroupIDs = Set(appState.groups.map(\.id))
        let ungrouped = filtered.filter { profile in
            guard let groupID = profile.groupID else { return true }
            return !validGroupIDs.contains(groupID)
        }

        List(selection: $appState.selectedProfileIDs) {
            if appState.searchText.isEmpty, !appState.recentProfiles.isEmpty {
                Section(appState.strings.t("nav.recent")) {
                    ForEach(appState.recentProfiles.prefix(4)) { profile in
                        profileRow(profile)
                    }
                }
            }

            ForEach(appState.groups) { group in
                let members = profilesByGroup[group.id] ?? []
                if !members.isEmpty || appState.searchText.isEmpty {
                    Section {
                        ForEach(members) { profile in
                            profileRow(profile)
                        }
                    } header: {
                        groupHeader(group)
                    }
                }
            }

            Section(appState.strings.connectionsTitle) {
                ForEach(ungrouped) { profile in
                    profileRow(profile)
                }
            }
        }
        .searchable(text: $appState.searchText)
        .onDeleteCommand {
            requestDelete(ids: appState.selectedProfileIDs)
        }
        .safeAreaInset(edge: .bottom) {
            bottomControls
        }
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
            Button(appState.strings.t("common.cancel"), role: .cancel) {
                pendingDeleteIDs = []
            }
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

    private func groupHeader(_ group: ServerGroup) -> some View {
        HStack {
            Text(group.name)
            Spacer()
            Button {
                Task { await appState.deleteGroup(id: group.id) }
            } label: {
                Image(systemName: "trash").font(.caption2)
            }
            .buttonStyle(.borderless)
        }
    }

    private var bottomControls: some View {
        VStack(spacing: 6) {
            if appState.selectedProfileIDs.count > 1 {
                HStack {
                    Text("\(appState.selectedProfileIDs.count) \(appState.strings.t("transfers.items"))")
                        .font(SparkleTheme.Typography.caption)
                        .foregroundStyle(SparkleTheme.Colors.secondaryText)
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
        }
        .padding(SparkleTheme.Spacing.small)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }

    private func profileRow(_ profile: ConnectionProfile) -> some View {
        HStack(spacing: SparkleTheme.Spacing.small) {
            Image(
                systemName: profile.protocolType.isEncryptedByDefault
                    ? SparkleTheme.Symbols.sftp
                    : SparkleTheme.Symbols.ftpInsecure
            )
            .foregroundStyle(
                profile.protocolType.isEncryptedByDefault
                    ? SparkleTheme.Colors.encryptedBadge
                    : SparkleTheme.Colors.danger
            )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(profile.name)
                        .font(SparkleTheme.Typography.headline)
                    if profile.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                }
                Text("\(profile.username)@\(profile.host):\(profile.port)")
                    .font(SparkleTheme.Typography.caption)
                    .foregroundStyle(SparkleTheme.Colors.secondaryText)
            }
            Spacer()
            Text(profile.protocolType.rawValue.uppercased())
                .font(.caption2)
                .foregroundStyle(SparkleTheme.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .tag(profile.id)
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                Task { await appState.connect(profile: profile) }
            }
        )
        .contextMenu {
            profileContextMenu(for: profile)
        }
    }

    @ViewBuilder
    private func profileContextMenu(for profile: ConnectionProfile) -> some View {
        Button(appState.strings.connect) {
            Task { await appState.connect(profile: profile) }
        }
        Button(appState.strings.t("common.edit")) {
            editorMode = .edit(profile)
        }
        Button(appState.strings.t("conn.cloneConnection")) {
            Task { _ = await appState.cloneProfile(profile) }
        }
        Divider()
        if appState.selectedProfileIDs.count > 1, appState.selectedProfileIDs.contains(profile.id) {
            Button(
                "\(appState.strings.t("conn.deleteSelected")) (\(appState.selectedProfileIDs.count))",
                role: .destructive
            ) {
                requestDelete(ids: appState.selectedProfileIDs)
            }
        } else {
            Button(appState.strings.t("common.delete"), role: .destructive) {
                Task { await appState.deleteProfile(profile) }
            }
        }
    }

    private func requestDelete(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        pendingDeleteIDs = ids
        isConfirmingBatchDelete = true
    }
}
