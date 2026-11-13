import Foundation
import SparkleCore
@testable import SparklePersistence
import Testing

private actor InMemoryCredentialStore: CredentialStoreProtocol {
    private var secrets: [UUID: Data] = [:]

    func saveSecret(_ data: Data, for reference: SecretReference, requireTouchID _: Bool) async throws {
        secrets[reference.id] = data
    }

    func loadSecret(for reference: SecretReference, prompt _: String?) async throws -> Data {
        guard let data = secrets[reference.id] else {
            throw AppError.credentialNotFound(service: "Secret not found")
        }
        return data
    }

    func deleteSecret(for reference: SecretReference) async throws {
        secrets.removeValue(forKey: reference.id)
    }

    func hasSecret(for reference: SecretReference) async -> Bool {
        secrets[reference.id] != nil
    }

    func evaluateBiometricPolicy(reason _: String) async throws {}
}

@Suite("Internal Connection Export & Encrypted Backup Tests")
struct InternalConnectionExportTests {
    @Test("Sanitized export strips credentials and references for team sharing")
    func sanitizedExportOmitsSecrets() async throws {
        let credStore = InMemoryCredentialStore()
        let passRef = SecretReference(kind: .password)
        try await credStore.saveSecret(Data("super-secret-password".utf8), for: passRef, requireTouchID: false)

        let profile = ConnectionProfile(
            name: "Prod Bastion",
            host: "bastion.example.com",
            port: 2222,
            username: "admin",
            passwordRef: passRef
        )
        let group = ServerGroup(name: "Production Servers")

        let exportedData = try await InternalConnectionExporter.exportData(
            profiles: [profile],
            groups: [group],
            credentialStore: credStore,
            mode: .sanitizedWithoutSecrets
        )

        #expect(InternalConnectionExporter.isNativeExport(data: exportedData))
        #expect(!InternalConnectionExporter.isEncryptedArchive(data: exportedData))

        let report = try InternalConnectionExporter.parseToReport(data: exportedData)
        #expect(report.format == .nativeJSON)
        #expect(report.connections.count == 1)

        let imported = try #require(report.connections.first)
        #expect(imported.profile.name == "Prod Bastion")
        #expect(imported.profile.host == "bastion.example.com")
        #expect(imported.profile.passwordRef == nil)
        #expect(imported.transientSecret == nil)
        #expect(imported.secretStatus == .none)
    }

    @Test("Password-protected export encrypts archive with AES-256-GCM and decrypts with valid passphrase")
    func encryptedArchiveRoundTrip() async throws {
        let credStore = InMemoryCredentialStore()
        let passRef = SecretReference(kind: .password)
        try await credStore.saveSecret(Data("vault-secret-123".utf8), for: passRef, requireTouchID: false)

        let profile = ConnectionProfile(
            name: "Secure Storage",
            host: "vault.internal",
            port: 22,
            username: "root",
            passwordRef: passRef
        )
        let group = ServerGroup(name: "Internal Vault")

        let archiveData = try await InternalConnectionExporter.exportData(
            profiles: [profile],
            groups: [group],
            credentialStore: credStore,
            mode: .passwordProtected,
            passphrase: "CorrectHorseBatteryStaple!"
        )

        #expect(InternalConnectionExporter.isEncryptedArchive(data: archiveData))

        // Decryption with correct passphrase
        let report = try InternalConnectionExporter.parseToReport(
            data: archiveData,
            passphrase: "CorrectHorseBatteryStaple!"
        )
        #expect(report.format == .nativeJSON)
        #expect(report.connections.count == 1)

        let entry = try #require(report.connections.first)
        #expect(entry.profile.name == "Secure Storage")
        #expect(entry.transientSecret == Data("vault-secret-123".utf8))
        #expect(entry.secretStatus == .plaintextReady)
    }

    @Test("Password-protected export fails closed with incorrect passphrase")
    func encryptedArchiveFailsOnWrongPassphrase() async throws {
        let profile = ConnectionProfile(
            name: "Web Server",
            host: "web.example.com",
            username: "deploy"
        )
        let archiveData = try await InternalConnectionExporter.exportData(
            profiles: [profile],
            groups: [],
            credentialStore: nil,
            mode: .passwordProtected,
            passphrase: "ValidSecretPassphrase123"
        )

        #expect(throws: AppError.self) {
            _ = try InternalConnectionExporter.parseToReport(
                data: archiveData,
                passphrase: "WrongPassword!"
            )
        }
    }

    @Test("ExternalConnectionFileReader detects encrypted archives and native exports correctly")
    func externalReaderInspectionRouting() async throws {
        let profile = ConnectionProfile(
            name: "Dev Node",
            host: "dev.local",
            username: "dev"
        )
        let plainData = try await InternalConnectionExporter.exportData(
            profiles: [profile],
            groups: [],
            credentialStore: nil,
            mode: .sanitizedWithoutSecrets
        )
        let encryptedData = try await InternalConnectionExporter.exportData(
            profiles: [profile],
            groups: [],
            credentialStore: nil,
            mode: .passwordProtected,
            passphrase: "SuperSecretKey"
        )

        let plainReport = try ExternalConnectionFileReader.inspect(data: plainData, fileExtension: "sparklesftp")
        #expect(plainReport.format == .nativeJSON)
        #expect(plainReport.connections.count == 1)

        let encryptedReport = try ExternalConnectionFileReader.inspect(
            data: encryptedData,
            fileExtension: "sparklesftp"
        )
        #expect(encryptedReport.format == .encryptedArchive)
        #expect(encryptedReport.warnings.contains("ARCHIVE_ENCRYPTED_PASSPHRASE_REQUIRED"))
    }
}
