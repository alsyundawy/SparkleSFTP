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

    public init(
        appState: AppState,
        isShowingEditor: Binding<Bool>,
        editingProfile: Binding<ConnectionProfile?>
    ) {
        self.appState = appState
        self._isShowingEditor = isShowingEditor
        self._editingProfile = editingProfile
    }

    public var body: some View {
        List(selection: $appState.selectedProfileID) {
            Section(appState.strings.connectionsTitle) {
                ForEach(appState.filteredProfiles) { profile in
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
        }
        .searchable(text: $appState.searchText)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: SparkleTheme.Spacing.tiny) {
                Button {
                    editingProfile = nil
                    isShowingEditor = true
                } label: {
                    Label(appState.strings.newConnection, systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)

                Menu("Import") {
                    Button("~/.ssh/config") {
                        Task { await appState.importFromSSHConfig() }
                    }
                    Button("FileZilla XML / WinSCP INI...") {
                        isShowingImporter = true
                    }
                }
            }
            .padding(SparkleTheme.Spacing.small)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
        }
        .fileImporter(
            isPresented: $isShowingImporter,
            allowedContentTypes: [.xml, .plainText],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                Task { await appState.importExternalConnections(from: url) }
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
                        .frame(height: 90)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(SparkleTheme.Colors.subtleBorder))
                } else if authMethod != .anonymous && authMethod != .sshAgent {
                    SecureField("Password (Stored in Apple Keychain)", text: $secretInput)
                }
                TextField("Default Remote Path", text: $remotePath)
                Toggle("Favorite", isOn: $isFavorite)
                Toggle("Require Touch ID before connecting", isOn: $requireTouchID)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save") {
                    let built = ConnectionProfile(
                        id: existingProfile?.id ?? UUID(),
                        name: name.isEmpty ? host : name,
                        groupID: existingProfile?.groupID,
                        protocolType: protocolType,
                        host: host,
                        port: Int(port) ?? protocolType.defaultPort,
                        username: username,
                        authMethod: authMethod,
                        passwordRef: existingProfile?.passwordRef,
                        privateKeyRef: existingProfile?.privateKeyRef,
                        passphraseRef: existingProfile?.passphraseRef,
                        defaultRemotePath: RemotePath(rawValue: remotePath),
                        isFavorite: isFavorite,
                        requireTouchID: requireTouchID
                    )
                    let secret = secretInput
                    secretInput = ""
                    Task {
                        await appState.saveProfile(built, secretString: secret)
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(host.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(SparkleTheme.Spacing.large)
        .frame(width: 480)
        .onAppear {
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
        }
    }
}

public struct HostKeyVerificationSheet: View {
    @ObservedObject var appState: AppState
    let challenge: HostKeyChallenge

    public init(appState: AppState, challenge: HostKeyChallenge) {
        self.appState = appState
        self.challenge = challenge
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SparkleTheme.Spacing.medium) {
            Label(appState.strings.hostKeyUnknownTitle, systemImage: "checkmark.shield.fill")
                .font(SparkleTheme.Typography.title)
                .foregroundStyle(SparkleTheme.Colors.warning)

            Text("The authenticity of \(challenge.host):\(challenge.port) cannot be established yet.")
                .font(SparkleTheme.Typography.body)

            VStack(alignment: .leading, spacing: 4) {
                Text("Algorithm: \(challenge.algorithm)")
                Text("Fingerprint: \(challenge.fingerprintSHA256)")
            }
            .font(SparkleTheme.Typography.monoSmall)
            .padding(SparkleTheme.Spacing.small)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SparkleTheme.Colors.panelBackground)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            HStack {
                Spacer()
                Button("Reject", role: .cancel) {
                    appState.resolveHostChallenge(trusted: false)
                }
                Button("Trust & Save to Keychain") {
                    appState.resolveHostChallenge(trusted: true)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(SparkleTheme.Spacing.large)
        .frame(width: 480)
    }
}

public struct SecurityDiagnosticsView: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SparkleTheme.Spacing.medium) {
            HStack {
                Label(appState.strings.securityDiagnostics, systemImage: "lock.shield")
                    .font(SparkleTheme.Typography.title)
                Spacer()
                Button("Close") { dismiss() }
            }

            GroupBox("Security Baseline") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("• SSH Engine: apple/swift-nio-ssh >= 0.15.1 (CVE-2026-43798 mitigated)")
                    Text("• Keychain Isolation: kSecAttrAccessibleWhenUnlockedThisDeviceOnly (No iCloud sync)")
                    Text("• FTPS TLS Policy: SecTrustEvaluateWithError + OCSP + TLS 1.2+ (Zero downgrade)")
                    Text("• FTP Bridge: Clibcurl locked to ftp,ftps protocols (CVE-2025-15224 N/A)")
                }
                .font(SparkleTheme.Typography.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Trusted SSH Host Keys (TOFU)") {
                List {
                    ForEach(appState.trustedHosts.keys.sorted(), id: \.self) { hostPort in
                        if let entry = appState.trustedHosts[hostPort] {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(hostPort).font(SparkleTheme.Typography.headline)
                                    Text(entry.fingerprint).font(SparkleTheme.Typography.monoSmall)
                                }
                                Spacer()
                                Button("Revoke") {
                                    let parts = hostPort.split(separator: ":")
                                    if parts.count == 2, let port = Int(parts[1]) {
                                        let host = String(parts[0])
                                        Task {
                                            try? await appState.hostTrustStore.clearTrust(host: host, port: port)
                                            appState.trustedHosts = await appState.hostTrustStore.allTrustedHosts()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(minHeight: 160)
            }
        }
        .padding(SparkleTheme.Spacing.large)
        .frame(width: 600, height: 420)
    }
}
