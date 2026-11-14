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

    private func makeSampleProtocolProfiles(groupID: UUID) -> [ConnectionProfile] {
        [
            ConnectionProfile(
                name: "SFTP Node", groupID: groupID,
                protocolType: .sftp, host: "sftp.example.com",
                port: 22, username: "u"
            ),
            ConnectionProfile(
                name: "SCP Node", groupID: groupID,
                protocolType: .scp, host: "scp.example.com",
                port: 2222, username: "u"
            ),
            ConnectionProfile(
                name: "FTP Node", groupID: groupID,
                protocolType: .ftp, host: "ftp.example.com",
                port: 21, username: "u"
            ),
            ConnectionProfile(
                name: "FTPS Explicit Node", groupID: groupID,
                protocolType: .ftpsExplicit, host: "ftpes.example.com",
                port: 21, username: "u"
            ),
            ConnectionProfile(
                name: "FTPS Implicit Node", groupID: groupID,
                protocolType: .ftpsImplicit, host: "ftps.example.com",
                port: 990, username: "u"
            )
        ]
    }

    @Test("WinSCP INI export and import accurately preserves all protocols")
    func winSCPINIExportPreservesProtocols() throws {
        let group = ServerGroup(name: "Production Cluster")
        let profiles = makeSampleProtocolProfiles(groupID: group.id)
        let ini = ConfigExporter.exportToWinSCPINI(profiles: profiles, groups: [group])

        #expect(ini.contains("FSProtocol=0"))
        #expect(ini.contains("FSProtocol=1"))
        #expect(ini.contains("FSProtocol=5"))
        #expect(ini.contains("Ftps=1"))
        #expect(ini.contains("Ftps=2"))

        // Roundtrip import
        let report = try ExternalConnectionFileReader.inspect(data: Data(ini.utf8), fileExtension: "ini")
        #expect(report.format == ExternalImportFormat.winSCPINI)
        #expect(report.connections.count == 5)

        let byName: [String: ImportedConnection] = Dictionary(
            uniqueKeysWithValues: report.connections.map { ($0.profile.name, $0) }
        )
        #expect(byName["SFTP Node"]?.profile.protocolType == .sftp)
        #expect(byName["SCP Node"]?.profile.protocolType == .scp)
        #expect(byName["FTP Node"]?.profile.protocolType == .ftp)
        #expect(byName["FTPS Explicit Node"]?.profile.protocolType == .ftpsExplicit)
        #expect(byName["FTPS Implicit Node"]?.profile.protocolType == .ftpsImplicit)
    }

    @Test("FileZilla XML export accurately maps protocols")
    func fileZillaXMLExportPreservesProtocols() throws {
        let group = ServerGroup(name: "Sites")
        let sftpProfile = ConnectionProfile(
            name: "SFTP Site", groupID: group.id,
            protocolType: .sftp, host: "sftp.site.com",
            port: 22, username: "user"
        )
        let ftpProfile = ConnectionProfile(
            name: "FTP Site", groupID: group.id,
            protocolType: .ftp, host: "ftp.site.com",
            port: 21, username: "user"
        )
        let ftpsImplicitProfile = ConnectionProfile(
            name: "FTPS Implicit Site", groupID: group.id,
            protocolType: .ftpsImplicit, host: "ftps.site.com",
            port: 990, username: "user"
        )
        let ftpsExplicitProfile = ConnectionProfile(
            name: "FTPS Explicit Site", groupID: group.id,
            protocolType: .ftpsExplicit, host: "ftpes.site.com",
            port: 21, username: "user"
        )

        let xml = ConfigExporter.exportToFileZillaXML(
            profiles: [sftpProfile, ftpProfile, ftpsImplicitProfile, ftpsExplicitProfile],
            groups: [group]
        )

        #expect(xml.contains("<Protocol>0</Protocol>"))
        #expect(xml.contains("<Protocol>1</Protocol>"))
        #expect(xml.contains("<Protocol>3</Protocol>"))
        #expect(xml.contains("<Protocol>4</Protocol>"))

        let report = try ExternalConnectionFileReader.inspect(data: Data(xml.utf8), fileExtension: "xml")
        #expect(report.format == ExternalImportFormat.fileZillaXML)
        #expect(report.connections.count == 4)

        let byName: [String: ImportedConnection] = Dictionary(
            uniqueKeysWithValues: report.connections.map { ($0.profile.name, $0) }
        )
        #expect(byName["SFTP Site"]?.profile.protocolType == .sftp)
        #expect(byName["FTP Site"]?.profile.protocolType == .ftp)
        #expect(byName["FTPS Implicit Site"]?.profile.protocolType == .ftpsImplicit)
        #expect(byName["FTPS Explicit Site"]?.profile.protocolType == .ftpsExplicit)
    }
}
