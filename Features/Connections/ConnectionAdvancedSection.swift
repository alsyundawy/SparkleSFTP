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
        Section("Security, Key & Path Options") {
            if authMethod == .publicKey {
                HStack {
                    Button("Import Key File...") {
                        isPickingKeyFile = true
                    }
                    if options.privateKeyBookmarkData != nil {
                        Label("Scoped key bookmark saved", systemImage: "checkmark.seal.fill")
                            .font(SparkleTheme.Typography.caption)
                            .foregroundStyle(SparkleTheme.Colors.success)
                    }
                }
                SecureField("Optional Key Passphrase (Keychain)", text: $options.passphraseInput)
            }

            Picker("Server Group", selection: $options.groupID) {
                Text("None").tag(UUID?.none)
                ForEach(appState.groups) { group in
                    Text(group.name).tag(UUID?.some(group.id))
                }
            }

            TextField("Default Local Path (Optional)", text: $options.defaultLocalPath)
        }

        Section("Proxy & SSH Jump Host") {
            Picker("Proxy Type", selection: $options.proxyKind) {
                Text("None").tag(ProxyKind.none)
                Text("SOCKS5").tag(ProxyKind.socks5)
                Text("HTTP CONNECT").tag(ProxyKind.http)
            }
            if options.proxyKind != .none {
                TextField("Proxy Host", text: $options.proxyHost)
                TextField("Proxy Port", text: $options.proxyPort)
            }

            if protocolType == .sftp || protocolType == .scp {
                Picker("SSH Jump Host", selection: $options.jumpHostProfileID) {
                    Text("Direct Connection").tag(UUID?.none)
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

    public init(appState: AppState, request: CredentialPromptRequest) {
        self.appState = appState
        self.request = request
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SparkleTheme.Spacing.medium) {
            Label("Authentication Prompt", systemImage: "key.fill")
                .font(SparkleTheme.Typography.title)
            Text(request.promptTitle)
                .font(SparkleTheme.Typography.body)
            SecureField("Password / Verification Code (2FA OTP)", text: $secret)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    secret = ""
                    appState.resolveCredentialPrompt(nil)
                }
                Button("Continue") {
                    let value = secret
                    secret = ""
                    appState.resolveCredentialPrompt(value)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(SparkleTheme.Spacing.large)
        .frame(width: 420)
    }
}
