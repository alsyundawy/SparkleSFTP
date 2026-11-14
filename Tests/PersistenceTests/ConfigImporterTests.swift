import Foundation
import SparkleCore
@testable import SparklePersistence
import Testing

@Suite("Config Importer & Multi-Format Detection Tests")
struct ConfigImporterTests {
    @Test("Format auto-detection accurately identifies bundle types and external configs")
    func formatAutoDetection() {
        let vaultHeaderBytes = Data(SparkleVaultHeader.magicASCII.utf8)
        #expect(ConfigImporter.detectFormat(data: vaultHeaderBytes, filename: "backup.sparklevault") == .sparkleVault)

        let bundleJSON = Data("{\"magic\": \"sparklesftp.config\"}".utf8)
        #expect(ConfigImporter.detectFormat(data: bundleJSON, filename: "export.sparkleconfig") == .sparkleConfig)

        let fileZillaXML = Data("<FileZilla3><Servers></Servers></FileZilla3>".utf8)
        #expect(ConfigImporter.detectFormat(data: fileZillaXML, filename: "sitemanager.xml") == .fileZillaXML)

        let iniText = Data("[Sessions/Production]\nHostName=192.168.1.100".utf8)
        #expect(ConfigImporter.detectFormat(data: iniText, filename: "winscp.ini") == .winSCPINI)

        let openSSHText = Data("Host mybastion\n  HostName 10.0.0.1\n  User ubuntu".utf8)
        #expect(ConfigImporter.detectFormat(data: openSSHText, filename: "config") == .openSSHConfig)
    }

    @Test("Import plan identifies new profiles and conflicting existing profiles")
    func importPlanCalculation() {
        let existing = [
            ConnectionProfile(name: "Existing Node", host: "node1.internal", port: 22, username: "admin")
        ]
        let incoming = [
            ConnectionProfile(name: "Existing Node", host: "node1.internal", port: 22, username: "admin"),
            ConnectionProfile(name: "Fresh Node", host: "node2.internal", port: 22, username: "deploy")
        ]

        let payload = ConfigBundlePayload(profiles: incoming)
        let bundle = SparkleConfigBundle(payload: payload, integrity: ConfigBundleIntegrity(alg: "none", digest: ""))

        let plan = ConfigImporter.buildImportPlan(
            bundle: bundle,
            existingProfiles: existing,
            existingGroups: []
        )

        #expect(plan.newProfiles.count == 1)
        #expect(plan.newProfiles.first?.name == "Fresh Node")
        #expect(plan.conflictingProfiles.count == 1)
        #expect(plan.conflictingProfiles.first?.imported.name == "Existing Node")
    }
}
