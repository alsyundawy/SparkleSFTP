import SparkleCore
import SparkleDesignSystem
import SparkleSecurity
import SwiftUI

/// Explicit modal identity ensuring SwiftUI initializes Create vs Edit cleanly without stale sheet state.
public enum ConnectionEditorMode: Identifiable, Equatable {
    case create
    case edit(ConnectionProfile)

    public var id: String {
        switch self {
        case .create:
            return "create"
        case let .edit(profile):
            return "edit-\(profile.id.uuidString)"
        }
    }
}

public struct ConnectionEditorView: View {
    @ObservedObject var appState: AppState
    let existingProfile: ConnectionProfile?
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var protocolType: ProtocolType
    @State private var host: String
    @State private var port: String
    @State private var username: String
    @State private var authMethod: AuthMethod
    @State private var secretInput = ""
    @State private var rememberPassword: Bool
    @State private var hasStoredSecret = false
    @State private var remotePath: String
    @State private var isFavorite: Bool
    @State private var requireTouchID: Bool
    @State private var advanced: ConnectionAdvancedOptions

    public init(appState: AppState, existingProfile: ConnectionProfile?) {
        self.appState = appState
        self.existingProfile = existingProfile
        let defaultProto = existingProfile?.protocolType ?? .sftp
        _name = State(initialValue: existingProfile?.name ?? "")
        _protocolType = State(initialValue: defaultProto)
        _host = State(initialValue: existingProfile?.host ?? "")
        _port = State(initialValue: String(existingProfile?.port ?? defaultProto.defaultPort))
        _username = State(initialValue: existingProfile?.username ?? "")
        _authMethod = State(initialValue: existingProfile?.authMethod ?? .password)
        let hadStoredRef = existingProfile?.passwordRef != nil || existingProfile?.privateKeyRef != nil
        _rememberPassword = State(initialValue: existingProfile == nil ? true : hadStoredRef)
        _remotePath = State(initialValue: existingProfile?.defaultRemotePath.rawValue ?? "/")
        _isFavorite = State(initialValue: existingProfile?.isFavorite ?? false)
        _requireTouchID = State(initialValue: existingProfile?.requireTouchID ?? false)
        _advanced = State(initialValue: ConnectionAdvancedOptions(profile: existingProfile))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SparkleTheme.Spacing.medium) {
            Text(existingProfile == nil ? appState.strings.newConnection : appState.strings.t("nav.editConnection"))
                .font(SparkleTheme.Typography.title)

            if protocolType == .ftp {
                SecurityWarningBanner(message: appState.strings.plaintextFTPWarning)
            }

            Form {
                Section(appState.strings.t("conn.serverAndCreds")) {
                    TextField(appState.strings.t("conn.profileName"), text: $name)
                    Picker(appState.strings.t("conn.protocol"), selection: $protocolType) {
                        ForEach(ProtocolType.allCases) { proto in
                            Text(proto.displayName).tag(proto)
                        }
                    }
                    .onChange(of: protocolType) { newProto in
                        if existingProfile == nil {
                            port = String(newProto.defaultPort)
                        }
                    }
                    TextField(appState.strings.t("conn.host"), text: $host)
                    TextField(appState.strings.t("conn.port"), text: $port)
                    TextField(appState.strings.t("conn.username"), text: $username)
                    Picker(appState.strings.t("conn.authentication"), selection: $authMethod) {
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
                        SecureField(appState.strings.t("conn.passwordKeychain"), text: $secretInput)
                    }
                    if authMethod != .anonymous, authMethod != .sshAgent {
                        Toggle(appState.strings.t("conn.rememberPassword"), isOn: $rememberPassword)
                        if hasStoredSecret, secretInput.isEmpty, rememberPassword {
                            HStack(spacing: 8) {
                                Label(appState.strings.t("conn.savedInKeychain"), systemImage: "checkmark.seal.fill")
                                    .font(SparkleTheme.Typography.caption)
                                    .foregroundStyle(appState.activePalette.accentColor)
                                Spacer()
                                Button(appState.strings.t("conn.clearSavedSecret")) {
                                    rememberPassword = false
                                    hasStoredSecret = false
                                }
                                .buttonStyle(.borderless)
                                .font(SparkleTheme.Typography.caption)
                            }
                        }
                    }
                    TextField(appState.strings.t("conn.defaultRemotePath"), text: $remotePath)
                    Toggle(appState.strings.t("nav.favorite"), isOn: $isFavorite)
                    Toggle(appState.strings.t("conn.requireTouchID"), isOn: $requireTouchID)
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
        .sparkleWorkspaceSurface(appState.activePalette)
        .task {
            hasStoredSecret = await appState.hasSavedSecret(for: existingProfile)
            if hasStoredSecret {
                rememberPassword = true
            }
        }
    }

    private var editorButtons: some View {
        HStack {
            Spacer()
            Button(appState.strings.t("common.cancel"), role: .cancel) { dismiss() }
            Button(appState.strings.t("common.save")) { saveChanges() }
                .buttonStyle(.borderedProminent)
                .disabled(host.trimmingCharacters(in: .whitespaces).isEmpty)
        }
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
            jumpHostProfileID: existingProfile == nil ? advanced.jumpHostProfileID : updatedJumpHostID(),
            proxy: proxyConfig,
            defaultRemotePath: RemotePath(rawValue: remotePath),
            defaultLocalPath: localTrimmed.isEmpty ? nil : localTrimmed,
            isFavorite: isFavorite,
            requireTouchID: requireTouchID,
            lastConnectedAt: existingProfile?.lastConnectedAt,
            createdAt: existingProfile?.createdAt ?? Date()
        )
        let secret = secretInput
        let passphrase = advanced.passphraseInput
        let shouldClearSecrets = !rememberPassword
        secretInput = ""
        advanced.passphraseInput = ""
        Task {
            await appState.saveProfile(
                built,
                secretString: secret,
                passphraseString: passphrase,
                clearStoredSecrets: shouldClearSecrets
            )
            dismiss()
        }
    }

    private func updatedJumpHostID() -> UUID? {
        guard advanced.jumpHostProfileID != existingProfile?.id else { return nil }
        return advanced.jumpHostProfileID
    }
}
