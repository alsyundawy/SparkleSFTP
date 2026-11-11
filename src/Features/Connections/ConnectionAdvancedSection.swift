import SparkleCore
import SparkleDesignSystem
import SparkleNetworking
import SparkleSecurity
import SwiftUI
import UniformTypeIdentifiers

struct ConnectionAdvancedOptions {
    var groupID: UUID?
    var defaultLocalPath: String = ""
    var proxyKind: ProxyKind = .none
    var proxyHost: String = ""
    var proxyPort: String = "1080"
    var jumpHostProfileID: UUID?
    var passphraseInput: String = ""
    var privateKeyBookmarkData: Data?

    init(profile: ConnectionProfile? = nil) {
        guard let profile else { return }
        groupID = profile.groupID
        defaultLocalPath = profile.defaultLocalPath ?? ""
        proxyKind = profile.proxy.kind
        proxyHost = profile.proxy.host
        proxyPort = String(profile.proxy.port)
        jumpHostProfileID = profile.jumpHostProfileID
        privateKeyBookmarkData = profile.privateKeyBookmarkData
    }
}

struct ConnectionAdvancedSection: View {
    @ObservedObject var appState: AppState
    let editingProfileID: UUID?
    let authMethod: AuthMethod
    let protocolType: ProtocolType
    @Binding var options: ConnectionAdvancedOptions
    @Binding var secretInput: String
    @State private var isPickingKeyFile = false

    var body: some View {
        Section(appState.strings.t("conn.securityKeyPathOptions")) {
            if authMethod == .publicKey {
                HStack {
                    Button(appState.strings.t("conn.importKeyFile")) {
                        isPickingKeyFile = true
                    }
                    if options.privateKeyBookmarkData != nil {
                        Label(appState.strings.t("conn.scopedKeySaved"), systemImage: "checkmark.seal.fill")
                            .font(SparkleTheme.Typography.caption)
                            .foregroundStyle(SparkleTheme.Colors.success)
                    }
                }
                SecureField(appState.strings.t("conn.keyPassphrase"), text: $options.passphraseInput)
            }

            Picker(appState.strings.t("conn.serverGroup"), selection: $options.groupID) {
                Text(appState.strings.t("common.none")).tag(UUID?.none)
                ForEach(appState.groups) { group in
                    Text(group.name).tag(UUID?.some(group.id))
                }
            }

            TextField(appState.strings.t("conn.defaultLocalPath"), text: $options.defaultLocalPath)
        }

        Section(appState.strings.t("conn.proxyAndJump")) {
            Picker(appState.strings.t("conn.proxyType"), selection: $options.proxyKind) {
                Text(appState.strings.t("common.none")).tag(ProxyKind.none)
                Text("SOCKS5").tag(ProxyKind.socks5)
                Text("HTTP CONNECT").tag(ProxyKind.http)
            }
            if options.proxyKind != .none {
                TextField(appState.strings.t("conn.proxyHost"), text: $options.proxyHost)
                TextField(appState.strings.t("conn.proxyPort"), text: $options.proxyPort)
            }

            if protocolType == .sftp || protocolType == .scp {
                Picker(appState.strings.t("conn.sshJumpHost"), selection: $options.jumpHostProfileID) {
                    Text(appState.strings.t("conn.directConnection")).tag(UUID?.none)
                    ForEach(availableBastions) { candidate in
                        Text("\(candidate.name) (\(candidate.host))").tag(UUID?.some(candidate.id))
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $isPickingKeyFile,
            allowedContentTypes: [.data, .item, .plainText],
            allowsMultipleSelection: false
        ) { result in
            if case let .success(urls) = result, let keyURL = urls.first {
                importKeyFile(keyURL)
            }
        }
    }

    private var availableBastions: [ConnectionProfile] {
        appState.profiles.filter {
            $0.id != editingProfileID && ($0.protocolType == .sftp || $0.protocolType == .scp)
        }
    }

    private func importKeyFile(_ url: URL) {
        do {
            let bookmark = try SecurityScopedBookmarkManager.createBookmark(for: url)
            let pem = try SecurityScopedBookmarkManager.withScopedAccess(to: url) { scopedURL in
                try String(contentsOf: scopedURL, encoding: .utf8)
            }
            _ = try PrivateKeyParser.parsePrivateKey(pemString: pem)
            secretInput = pem
            options.privateKeyBookmarkData = bookmark
        } catch {
            appState.lastError = (error as? AppError) ?? .invalidPrivateKey(reason: error.localizedDescription)
        }
    }
}

public struct CredentialPromptSheet: View {
    @ObservedObject var appState: AppState
    let request: CredentialPromptRequest
    @State private var secret = ""
    @State private var rememberPassword: Bool

    public init(appState: AppState, request: CredentialPromptRequest) {
        self.appState = appState
        self.request = request
        _rememberPassword = State(initialValue: request.authMethod == .password)
    }

    public var body: some View {
        let palette = appState.activePalette
        VStack(alignment: .leading, spacing: SparkleTheme.Spacing.medium) {
            Label(appState.strings.t("conn.authPrompt"), systemImage: "key.fill")
                .font(SparkleTheme.Typography.title)
                .foregroundStyle(palette.accentColor)
            Text(request.promptTitle)
                .font(SparkleTheme.Typography.body)
            SecureField(appState.strings.t("conn.otpPlaceholder"), text: $secret)
                .textFieldStyle(.roundedBorder)
            Toggle(appState.strings.t("conn.rememberPassword"), isOn: $rememberPassword)
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button(appState.strings.t("common.cancel"), role: .cancel) {
                    secret = ""
                    appState.resolveCredentialPrompt(nil, remember: false)
                }
                Button(appState.strings.t("common.continue")) {
                    let value = secret
                    secret = ""
                    appState.resolveCredentialPrompt(value, remember: rememberPassword)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(SparkleTheme.Spacing.large)
        .frame(width: 460, height: 220)
        .sparkleWorkspaceSurface(palette)
    }
}
