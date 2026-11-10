import Foundation
import SparkleCore
@testable import SparklePersistence
import Testing

@Suite("SparklePersistence Tests")
struct PersistenceTests {
    @Test("ConnectionStore saves and loads profiles atomically without storing secrets")
    func connectionStoreRoundTripAndNoSecrets() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SparkleStore-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let storeURL = dir.appendingPathComponent("connections.json")
        let store = ConnectionStore(fileURL: storeURL)

        let secretRef = SecretReference(kind: .password)
        let profile = ConnectionProfile(
            name: "Production EU",
            protocolType: .sftp,
            host: "eu.prod.internal",
            port: 2222,
            username: "deploy",
            authMethod: .password,
            passwordRef: secretRef,
            isFavorite: true
        )

        try await store.saveProfile(profile)
        let loaded = try await store.loadProfiles()
        #expect(loaded.count == 1)
        #expect(loaded.first?.host == "eu.prod.internal")
        #expect(loaded.first?.passwordRef == secretRef)

        let rawJSON = try String(contentsOf: storeURL, encoding: .utf8)
        #expect(rawJSON.contains("\"schemaVersion\" : 1"))
        #expect(!rawJSON.contains("supersecretpassword"))
    }

    @Test("TransferJournal persists checkpoints, reconciles crashes, and enforces retention")
    func transferJournalWALAndRecovery() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SparkleJournal-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let dbURL = dir.appendingPathComponent("journal.sqlite3")
        let journal = try TransferJournal(databaseURL: dbURL)

        let activeID = UUID()
        let completedID = UUID()
        let activeMeta = TransferTaskMetadata(
            id: activeID,
            direction: .download,
            source: .remote(profileID: UUID(), host: "srv", path: "/large.iso"),
            destination: .local(url: dir.appendingPathComponent("large.iso")),
            totalBytes: 1_000_000
        )
        let completedMeta = TransferTaskMetadata(
            id: completedID,
            direction: .upload,
            source: .local(url: dir.appendingPathComponent("note.txt")),
            destination: .remote(profileID: UUID(), host: "srv", path: "/note.txt"),
            totalBytes: 100
        )

        try await journal.upsert(
            TransferJournalRecord(
                id: activeID,
                metadata: activeMeta,
                statusCode: "transferring",
                checkpoint: TransferCheckpoint(
                    bytesTransferred: 500_000,
                    remoteSize: 1_000_000,
                    remoteModificationTime: nil
                )
            )
        )
        try await journal.upsert(
            TransferJournalRecord(
                id: completedID,
                metadata: completedMeta,
                statusCode: "completed",
                updatedAt: Date().addingTimeInterval(-40 * 86_400)
            )
        )

        let reconciled = try await journal.reconcileInterruptedOnLaunch()
        #expect(reconciled.count == 1)
        #expect(reconciled.first?.id == activeID)
        #expect(reconciled.first?.statusCode == "interrupted")

        try await journal.pruneOldEntries(maxEntries: 10_000, maxAgeDays: 30)
        let remaining = try await journal.fetchAll()
        #expect(remaining.count == 1)
        #expect(remaining.first?.id == activeID)
    }

    @Test("SSHConfigParser extracts Host, HostName, Port, User, IdentityFile, and skips wildcards")
    func sshConfigParserTest() {
        let config = """
        # Global defaults
        Host *
          ServerAliveInterval 60

        Host bastion prod-web
          HostName 203.0.113.10
          Port 2222
          User ops
          IdentityFile ~/.ssh/id_ed25519
          ProxyJump jump.internal
        """
        let home = URL(fileURLWithPath: "/Users/tester")
        let entries = SSHConfigParser.parse(contents: config, homeDirectory: home)
        #expect(entries.count == 2)
        #expect(entries[0].alias == "bastion")
        #expect(entries[0].hostName == "203.0.113.10")
        #expect(entries[0].port == 2222)
        #expect(entries[0].user == "ops")
        #expect(entries[0].identityFile == "/Users/tester/.ssh/id_ed25519")
        #expect(entries[0].proxyJump == "jump.internal")
    }

    @Test("FileZilla XML and WinSCP INI importers extract endpoints cleanly")
    func externalImportersTest() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <FileZilla3>
          <Servers>
            <Server>
              <Host>files.example.org</Host>
              <Port>21</Port>
              <Protocol>4</Protocol>
              <Logontype>1</Logontype>
              <User>alice</User>
              <Name>Staging FTPS</Name>
              <RemoteDir>1 0 3 var 3 www</RemoteDir>
            </Server>
          </Servers>
        </FileZilla3>
        """
        let fileZillaItems = try FileZillaImporter.parse(xmlData: Data(xml.utf8))
        #expect(fileZillaItems.count == 1)
        #expect(fileZillaItems[0].profile.protocolType == .ftpsExplicit)
        #expect(fileZillaItems[0].profile.defaultRemotePath.rawValue == "/var/www")

        let ini = """
        [Sessions\\Prod%20SFTP]
        HostName=sftp.example.net
        PortNumber=2200
        UserName=deploy
        FSProtocol=0
        RemoteDirectory=/srv/app
        """
        let winscp = WinSCPIniImporter.parse(iniContents: ini)
        #expect(winscp.count == 1)
        #expect(winscp[0].profile.name == "Prod SFTP")
        #expect(winscp[0].profile.port == 2200)
        #expect(winscp[0].profile.protocolType == .sftp)
    }
}
