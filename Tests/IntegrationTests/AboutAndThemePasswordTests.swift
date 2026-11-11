import Foundation
import SparkleCore
@testable import SparkleDesignSystem
@testable import SparkleFeatures
@testable import SparkleNetworking
@testable import SparklePersistence
@testable import SparkleTerminal
import Testing

private actor EphemeralPasswordStore: CredentialStoreProtocol {
    private var secrets: [String: Data] = [:]

    func saveSecret(_ data: Data, for reference: SecretReference, requireTouchID _: Bool) async throws {
        secrets[reference.accountKey] = data
    }

    func loadSecret(for reference: SecretReference, prompt _: String?) async throws -> Data {
        guard let data = secrets[reference.accountKey] else {
            throw AppError.keychainFailure(status: -25300, message: "Missing secret")
        }
        return data
    }

    func deleteSecret(for reference: SecretReference) async throws {
        secrets.removeValue(forKey: reference.accountKey)
    }

    func hasSecret(for reference: SecretReference) async -> Bool {
        secrets[reference.accountKey] != nil
    }
}

private actor PromptCaptureFlag {
    private(set) var capturedRequest: CredentialPromptRequest?

    func record(_ request: CredentialPromptRequest) {
        capturedRequest = request
    }
}

@Suite("About Dialog, Full Theme Propagation & Remember Password Tests")
struct AboutAndThemePasswordTests {
    @Test("Remember password flow saves, inspects, and explicitly clears Keychain secrets")
    @MainActor
    func rememberAndClearPasswordLifecycle() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SparkleRemember-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let creds = EphemeralPasswordStore()
        let appState = AppState(
            credentialStore: creds,
            connectionStore: ConnectionStore(fileURL: dir.appendingPathComponent("conn.json")),
            transferJournal: nil,
            snippetStore: CommandSnippetStore(fileURL: dir.appendingPathComponent("snippets.json"))
        )

        let profile = ConnectionProfile(
            name: "Remember Test",
            protocolType: .sftp,
            host: "sftp.example.com",
            port: 22,
            username: "deploy"
        )
        await appState.saveProfile(profile, secretString: nil, passphraseString: nil)
        let savedNoSecret = try #require(appState.profiles.first)
        let savedBefore = await appState.hasSavedSecret(for: savedNoSecret)
        #expect(!savedBefore)

        appState.resolveCredentialPrompt("prompted-pass", remember: true)
        #expect(appState.pendingPromptedSecretToRemember == "prompted-pass")
        appState.resolveCredentialPrompt("prompted-pass", remember: false)
        #expect(appState.pendingPromptedSecretToRemember == nil)

        await appState.saveProfile(savedNoSecret, secretString: "saved-secret-123", passphraseString: nil)
        let savedWithSecret = try #require(appState.profiles.first)
        let ref = try #require(savedWithSecret.passwordRef)
        let savedNow = await appState.hasSavedSecret(for: savedWithSecret)
        #expect(savedNow)

        await appState.saveProfile(
            savedWithSecret,
            secretString: nil,
            passphraseString: nil,
            clearStoredSecrets: true
        )
        let clearedProfile = try #require(appState.profiles.first)
        #expect(clearedProfile.passwordRef == nil)
        let savedAfterClear = await appState.hasSavedSecret(for: clearedProfile)
        #expect(!savedAfterClear)
        let storeStillHasSecret = await creds.hasSecret(for: ref)
        #expect(!storeStillHasSecret)
    }

    @Test("FTPService invokes credentialPrompt when password profile lacks stored secret")
    func ftpCredentialPromptInvocation() async {
        let creds = EphemeralPasswordStore()
        let flag = PromptCaptureFlag()
        let profile = ConnectionProfile(
            name: "FTP Prompt",
            protocolType: .ftp,
            host: "127.0.0.1",
            port: 1,
            username: "ftpuser",
            authMethod: .password
        )
        let ftp = FTPService(profile: profile, credentialStore: creds) { request in
            await flag.record(request)
            return "runtime-ftp-secret"
        }

        try? await ftp.connect()
        let captured = await flag.capturedRequest
        #expect(captured?.host == "127.0.0.1")
        #expect(captured?.username == "ftpuser")
        #expect(captured?.authMethod == .password)
    }

    @Test("Workspace theme propagation updates Terminal colors and About diagnostics")
    @MainActor
    func themePropagationAndAboutDiagnostics() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SparkleAboutTheme-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let appState = AppState(
            credentialStore: EphemeralPasswordStore(),
            connectionStore: ConnectionStore(fileURL: dir.appendingPathComponent("conn.json")),
            transferJournal: nil,
            snippetStore: CommandSnippetStore(fileURL: dir.appendingPathComponent("snippets.json"))
        )

        let dracula = SparkleThemeCatalog.palette(id: "dracula", appearanceMode: .dark, systemIsDark: true)
        appState.selectTheme(dracula)
        let darkPalette = appState.activePalette
        #expect(darkPalette.isDark)
        let darkTerminal = TerminalThemeColors(
            backgroundHex: darkPalette.canvasHex,
            foregroundHex: darkPalette.primaryTextHex,
            caretHex: darkPalette.accentHex,
            selectionHex: darkPalette.accentHex
        )
        #expect(darkTerminal.backgroundHex == darkPalette.canvasHex)
        #expect(darkTerminal.caretHex == darkPalette.accentHex)

        let diagnostics = AboutView(appState: appState).buildDiagnosticsText()
        #expect(diagnostics.contains("SparkleSFTP v"))
        #expect(diagnostics.contains(darkPalette.displayName))
        #expect(AboutTabKind.allCases.count == 7)
        #expect(AboutTabKind.allCases.contains(.libraries))

        for code in ["en", "id"] {
            appState.selectLocale(code: code)
            for tab in AboutTabKind.allCases {
                let title = tab.title(strings: appState.strings)
                #expect(!title.hasPrefix("about."))
            }
        }
    }

    @Test("Connection row keys remain unique across Recent and Group sections with 285+ i18n keys")
    func connectionRowKeysAndLocalizationParity() {
        let enStrings = LocalizationCatalog.loadBundledStrings(code: "en")
        let idStrings = LocalizationCatalog.loadBundledStrings(code: "id")
        #expect(enStrings.count >= 285)
        #expect(idStrings.count == enStrings.count)
        for key in ["about.aboutTab", "about.tagline", "conn.rememberPassword", "conn.savedInKeychain"] {
            #expect(enStrings[key] != nil)
            #expect(idStrings[key] != nil)
        }

        let group = ServerGroup(name: "Prod")
        let recentAndGrouped = ConnectionProfile(
            name: "Edge",
            groupID: group.id,
            protocolType: .sftp,
            host: "edge.internal",
            port: 22,
            username: "ops"
        )
        let rows = ConnectionManagerView.buildTableRows(
            filteredProfiles: [recentAndGrouped],
            recentProfiles: [recentAndGrouped],
            groups: [group],
            searchText: "",
            strings: AppStrings()
        )
        let rowKeys: [String] = rows.compactMap { item in
            switch item {
            case let .section(id, _, _): return id
            case let .profile(_, rowKey): return rowKey
            }
        }
        // Recent + Grouped duplicate profile must receive distinct NSTableView rowKeys
        #expect(rowKeys.contains("recent-\(recentAndGrouped.id.uuidString)"))
        #expect(rowKeys.contains("grp-\(group.id.uuidString)-\(recentAndGrouped.id.uuidString)"))
        #expect(Set(rowKeys).count == rowKeys.count)
    }
}
