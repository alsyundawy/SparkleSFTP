import SparkleCore
import SparkleDesignSystem
import SparkleSecurity
import SwiftUI
import UniformTypeIdentifiers

public struct ConnectionManagerView: View {
    @ObservedObject var appState: AppState
    @Binding var isShowingEditor: Bool
    @Binding var editingProfile: ConnectionProfile?
    @State private var isShowingImporter = false
    @State private var isAddingGroup = false
    @State private var newGroupName = ""

    public init(
        appState: AppState,
        isShowingEditor: Binding<Bool>,
        editingProfile: Binding<ConnectionProfile?>
    ) {
        self.appState = appState
        _isShowingEditor = isShowingEditor
        _editingProfile = editingProfile
    }

    public var body: some View {
        List(selection: $appState.selectedProfileID) {
            if appState.searchText.isEmpty, !appState.recentProfiles.isEmpty {
                Section("Recent") {
                    ForEach(appState.recentProfiles.prefix(4)) { profile in
                        profileRow(profile)
                    }
                }
            }

            ForEach(appState.groups) { group in
                let members = appState.filteredProfiles.filter { $0.groupID == group.id }
                if !members.isEmpty || appState.searchText.isEmpty {
                    Section {
                        ForEach(members) { profile in
                            profileRow(profile)
                        }
                    } header: {
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
                }
            }

            Section(appState.strings.connectionsTitle) {
                let ungrouped = appState.filteredProfiles.filter { profile in
                    profile.groupID == nil || !appState.groups.contains { $0.id == profile.groupID }
                }
                ForEach(ungrouped) { profile in
                    profileRow(profile)
                }
            }
        }
        .searchable(text: $appState.searchText)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 4) {
                HStack(spacing: SparkleTheme.Spacing.tiny) {
                    Button {
                        editingProfile = nil
                        isShowingEditor = true
                    } label: {
                        Label(appState.strings.newConnection, systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)

                    Button("+ Group") {
                        isAddingGroup = true
                    }

                    Menu("Import") {
                        Button("~/.ssh/config") {
                            Task { await appState.importFromSSHConfig() }
                        }
                        Button("FileZilla XML / WinSCP INI...") {
                            isShowingImporter = true
                        }
                    }
                }
            }
            .padding(SparkleTheme.Spacing.small)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
        }
        .alert("New Server Group", isPresented: $isAddingGroup) {
            TextField("Group name", text: $newGroupName)
            Button("Cancel", role: .cancel) { newGroupName = "" }
            Button("Create") {
                let name = newGroupName
                newGroupName = ""
                Task { await appState.createGroup(named: name) }
            }
        }
        .fileImporter(
            isPresented: $isShowingImporter,
            allowedContentTypes: [.xml, .plainText],
            allowsMultipleSelection: false
        ) { result in
            if case let .success(urls) = result, let url = urls.first {
                Task { await appState.importExternalConnections(from: url) }
            }
        }
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
        .tag(profile.id)
        .contextMenu {
            Button(appState.strings.connect) {
                Task { await appState.connect(profile: profile) }
            }
            Button("Edit") {
                editingProfile = profile
                isShowingEditor = true
            }
            Divider()
            Button("Delete", role: .destructive) {
                Task { await appState.deleteProfile(profile) }
            }
        }
    }
}

public struct ConnectionEditorView: View {
    @ObservedObject var appState: AppState
    let existingProfile: ConnectionProfile?
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var protocolType: ProtocolType = .sftp
    @State private var host = ""
    @State private var port = "22"
    @State private var username = ""
    @State private var authMethod: AuthMethod = .password
    @State private var secretInput = ""
    @State private var remotePath = "/"
    @State private var isFavorite = false
    @State private var requireTouchID = false
    @State private var advanced = ConnectionAdvancedOptions()

    public init(appState: AppState, existingProfile: ConnectionProfile?) {
        self.appState = appState
        self.existingProfile = existingProfile
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SparkleTheme.Spacing.medium) {
            Text(existingProfile == nil ? appState.strings.newConnection : "Edit Connection")
                .font(SparkleTheme.Typography.title)

            if protocolType == .ftp {
                SecurityWarningBanner(message: appState.strings.plaintextFTPWarning)
            }

            Form {
                Section("Server & Credentials") {
                    TextField("Profile Name", text: $name)
                    Picker("Protocol", selection: $protocolType) {
                        ForEach(ProtocolType.allCases) { proto in
                            Text(proto.displayName).tag(proto)
                        }
                    }
                    .onChange(of: protocolType) { newProto in
                        if existingProfile == nil {
                            port = String(newProto.defaultPort)
                        }
                    }
                    TextField("Host", text: $host)
                    TextField("Port", text: $port)
                    TextField("Username", text: $username)
                    Picker("Authentication", selection: $authMethod) {
                        ForEach(AuthMethod.allCases) { method in
                            Text(method.rawValue).tag(method)
                        }
                    }
                    if authMethod == .publicKey {
                        TextEditor(text: $secretInput)
                            .font(SparkleTheme.Typography.monoSmall)
                            .frame(height: 80)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(SparkleTheme.Colors.subtleBorder))
                    } else if authMethod != .anonymous, authMethod != .sshAgent {
                        SecureField("Password (Stored in Apple Keychain)", text: $secretInput)
                    }
                    TextField("Default Remote Path", text: $remotePath)
                    Toggle("Favorite", isOn: $isFavorite)
                    Toggle("Require Touch ID before connecting", isOn: $requireTouchID)
                }

                ConnectionAdvancedSection(
                    appState: appState,
                    editingProfileID: existingProfile?.id,
                    authMethod: authMethod,
                    protocolType: protocolType,
                    options: $advanced,
                    secretInput: $secretInput
                )
            }
            .formStyle(.grouped)

            editorButtons
        }
        .padding(SparkleTheme.Spacing.large)
        .frame(width: 520, height: 640)
        .onAppear(perform: populateExistingFields)
    }

    private var editorButtons: some View {
        HStack {
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }
            Button("Save") { saveChanges() }
                .buttonStyle(.borderedProminent)
                .disabled(host.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func populateExistingFields() {
        guard let existing = existingProfile else { return }
        name = existing.name
        protocolType = existing.protocolType
        host = existing.host
        port = String(existing.port)
        username = existing.username
        authMethod = existing.authMethod
        remotePath = existing.defaultRemotePath.rawValue
        isFavorite = existing.isFavorite
        requireTouchID = existing.requireTouchID
        advanced.groupID = existing.groupID
        advanced.defaultLocalPath = existing.defaultLocalPath ?? ""
        advanced.proxyKind = existing.proxy.kind
        advanced.proxyHost = existing.proxy.host
        advanced.proxyPort = String(existing.proxy.port)
        advanced.jumpHostProfileID = existing.jumpHostProfileID
        advanced.privateKeyBookmarkData = existing.privateKeyBookmarkData
    }

    private func saveChanges() {
        let localTrimmed = advanced.defaultLocalPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let proxyConfig = ProxyConfiguration(
            kind: advanced.proxyKind,
            host: advanced.proxyHost.trimmingCharacters(in: .whitespacesAndNewlines),
            port: Int(advanced.proxyPort) ?? 1080
        )
        let built = ConnectionProfile(
            id: existingProfile?.id ?? UUID(),
            name: name.isEmpty ? host : name,
            groupID: advanced.groupID,
            protocolType: protocolType,
            host: host,
            port: Int(port) ?? protocolType.defaultPort,
            username: username,
            authMethod: authMethod,
            passwordRef: existingProfile?.passwordRef,
            privateKeyRef: existingProfile?.privateKeyRef,
            passphraseRef: existingProfile?.passphraseRef,
            privateKeyBookmarkData: advanced.privateKeyBookmarkData,
            jumpHostProfileID: advanced.jumpHostProfileID,
            proxy: proxyConfig,
            defaultRemotePath: RemotePath(rawValue: remotePath),
            defaultLocalPath: localTrimmed.isEmpty ? nil : localTrimmed,
            isFavorite: isFavorite,
            requireTouchID: requireTouchID
        )
        let secret = secretInput
        let passphrase = advanced.passphraseInput
        secretInput = ""
        advanced.passphraseInput = ""
        Task {
            await appState.saveProfile(built, secretString: secret, passphraseString: passphrase)
            dismiss()
        }
    }
}
