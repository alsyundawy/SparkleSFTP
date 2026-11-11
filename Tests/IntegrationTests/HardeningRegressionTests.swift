import Foundation
import SparkleCore
@testable import SparkleDesignSystem
@testable import SparkleFeatures
@testable import SparkleFileManager
@testable import SparkleNetworking
@testable import SparklePersistence
@testable import SparkleSecurity
@testable import SparkleTerminal
import Testing

@Suite("App-Wide Hardening Regression Tests")
struct HardeningRegressionTests {
    @Test("AppStrings resolves conn.password cleanly across English and Indonesian locales")
    func localeIncludesConnPasswordKey() {
        let enStrings = AppStrings(language: .english)
        let idStrings = AppStrings(language: .indonesian)
        #expect(enStrings.t("conn.password") == "Password")
        #expect(idStrings.t("conn.password") == "Kata Sandi")
    }

    @Test("EditorTextEncoding UTF-16LE roundtrip avoids double BOM prefix")
    func editorUTF16LERoundtripDoesNotDoubleBOM() {
        var raw = Data([0xFF, 0xFE])
        if let body = "hello\n".data(using: .utf16LittleEndian) {
            raw.append(body)
        }
        let decoded = EditorTextEncoding.decode(raw)
        #expect(decoded.encoding == .utf16LE)
        #expect(decoded.text == "hello\n")

        let reencoded = decoded.encoding.encode(decoded.text)
        #expect(reencoded == raw)
    }

    @Test("ExternalTerminalLauncher adds -- delimiter and rejects leading-hyphen SSH targets")
    func externalTerminalLauncherPreventsOptionInjection() throws {
        let cleanProfile = ConnectionProfile(name: "Box", protocolType: .sftp, host: "example.com", username: "deploy")
        let args = try ExternalTerminalLauncher.buildOpenSSHCommandParts(for: cleanProfile)
        #expect(args.suffix(2) == ["--", "deploy@example.com"])

        let injectedUser = ConnectionProfile(
            name: "Bad",
            protocolType: .sftp,
            host: "example.com",
            username: "-oProxyCommand=calc"
        )
        #expect(throws: AppError.invalidConfiguration("Unsupported leading hyphen in SSH username")) {
            _ = try ExternalTerminalLauncher.buildOpenSSHCommandParts(for: injectedUser)
        }
    }

    @Test("LocalFileService rejects CWE-22 traversal components on createDirectory and rename")
    func localFileServiceRejectsTraversal() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SparkleLocalSec-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let service = LocalFileService()
        var threwMkdirTraversal = false
        do {
            _ = try await service.createDirectory(named: "../escape", in: root)
        } catch AppError.pathTraversal {
            threwMkdirTraversal = true
        }
        #expect(threwMkdirTraversal)

        let sample = root.appendingPathComponent("a.txt")
        try Data("x".utf8).write(to: sample)
        var threwRenameTraversal = false
        do {
            _ = try await service.rename(itemAt: sample, to: "../b.txt")
        } catch AppError.pathTraversal {
            threwRenameTraversal = true
        }
        #expect(threwRenameTraversal)
    }

    @Test("AppState Esc cancellation helpers resume pending continuations cleanly")
    @MainActor
    func appStateEscCancellationHelpersPreventHang() async {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SparkleEsc-\(UUID())")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let state = AppState(
            connectionStore: ConnectionStore(fileURL: dir.appendingPathComponent("conn.json")),
            transferJournal: nil,
            snippetStore: CommandSnippetStore(fileURL: dir.appendingPathComponent("snip.json"))
        )

        let hostTask = Task {
            await state.promptHostKeyChallenge(
                HostKeyChallenge(host: "srv", port: 22, algorithm: "ssh-ed25519", fingerprintSHA256: "SHA256:x")
            )
        }
        try? await Task.sleep(for: .milliseconds(20))
        state.pendingHostChallenge = nil
        state.cancelPendingHostChallengeIfNeeded()
        #expect(await hostTask.value == false)

        let credTask = Task {
            await state.promptCredential(
                CredentialPromptRequest(host: "srv", port: 22, username: "u", authMethod: .password, promptTitle: "Pw")
            )
        }
        try? await Task.sleep(for: .milliseconds(20))
        state.pendingCredentialPrompt = nil
        state.cancelPendingCredentialPromptIfNeeded()
        #expect(await credTask.value == nil)
    }

    @Test("SparkleThemeStore validates all 11 palette hex fields")
    func themeStoreValidatesAllHexFields() {
        var bad = SparkleThemeCatalog.defaultLight
        bad = SparkleThemePalette(
            id: "broken",
            displayName: "Broken",
            family: "Test",
            isDark: false,
            windowHex: bad.windowHex,
            canvasHex: bad.canvasHex,
            borderHex: "NOTHEX",
            primaryTextHex: bad.primaryTextHex,
            secondaryTextHex: bad.secondaryTextHex,
            accentHex: bad.accentHex,
            keywordHex: bad.keywordHex,
            functionHex: bad.functionHex,
            stringHex: bad.stringHex,
            numberHex: bad.numberHex,
            operatorHex: bad.operatorHex
        )
        #expect(!SparkleThemeStore.isValidPalette(bad))
        #expect(SparkleThemeStore.isValidPalette(SparkleThemeCatalog.defaultDark))
    }
}
