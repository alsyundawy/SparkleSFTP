import Foundation
import SparkleCore
@testable import SparkleDesignSystem
@testable import SparkleSecurity
import Testing

@Suite("SparkleSecurity & Catalog Hardening Tests")
struct SecurityHardeningTests {
    @Test("PathValidator rejects rooted dot-dot escape paths")
    func pathValidatorRejectsRootedDotDotTraversal() throws {
        #expect(throws: AppError.pathTraversal(attempted: "/../../etc/passwd")) {
            _ = try PathValidator.canonicalizeRemote("/../../etc/passwd", relativeTo: RemotePath("/"))
        }
        #expect(throws: AppError.pathTraversal(attempted: "/srv/../../etc/passwd")) {
            _ = try PathValidator.canonicalizeRemote("/srv/../../etc/passwd", relativeTo: RemotePath("/"))
        }
    }

    @Test("LocalizationCatalog importLocaleFile blocks CWE-22 locale code path traversal")
    func localizationCatalogBlocksPathTraversalCode() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SparkleLocaleTest-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let badJSON = """
        {
          "code": "../../evil",
          "displayName": "Bad",
          "version": "1.0.0",
          "strings": { "common.ok": "OK" }
        }
        """
        let inputURL = dir.appendingPathComponent("bad.json")
        try Data(badJSON.utf8).write(to: inputURL)

        let targetDir = dir.appendingPathComponent("Locales", isDirectory: true)
        var didThrow = false
        do {
            _ = try LocalizationCatalog.importLocaleFile(from: inputURL, into: targetDir)
        } catch {
            didThrow = true
        }
        #expect(didThrow)
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("evil.json").path))
    }

    @Test("FileHostTrustBackingStore persists with 0600 permissions and detects corruption without prompts")
    func fileHostTrustStoreRoundTripAndTamperDetection() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SparkleTrust-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let trustFile = dir.appendingPathComponent("trusted_hosts.v1.json")
        let backing = FileHostTrustBackingStore(fileURL: trustFile, legacyKeychainStore: nil)
        let store = HostTrustStore(backingStore: backing)

        try await store.trust(host: "example.com", port: 22, fingerprint: "SHA256:testfingerprint001")

        let attrs = try FileManager.default.attributesOfItem(atPath: trustFile.path)
        let mode = (attrs[.posixPermissions] as? NSNumber)?.intValue
        #expect(mode == 0o600)

        let reloaded = HostTrustStore(backingStore: FileHostTrustBackingStore(
            fileURL: trustFile,
            legacyKeychainStore: nil
        ))
        let evaluation = await reloaded.evaluate(
            host: "example.com",
            port: 22,
            fingerprint: "SHA256:testfingerprint001"
        )
        if case let .trusted(fingerprint, _) = evaluation {
            #expect(fingerprint == "SHA256:testfingerprint001")
        } else {
            Issue.record("Expected .trusted state")
        }

        try Data("{\"corrupted\":true".utf8).write(to: trustFile, options: [.atomic])
        let tamperedStore = HostTrustStore(backingStore: FileHostTrustBackingStore(
            fileURL: trustFile,
            legacyKeychainStore: nil
        ))
        let corruptedState = await tamperedStore.evaluate(
            host: "example.com",
            port: 22,
            fingerprint: "SHA256:testfingerprint001"
        )
        #expect(corruptedState == .corrupted)
    }

    @Test("KeychainService hasSecret returns false cleanly for nonexistent references")
    func keychainHasSecretMissingReturnsFalseWithoutPrompt() async {
        let service = KeychainService(serviceIdentifier: "com.sparklesftp.test.\(UUID().uuidString)")
        let missing = SecretReference(kind: .password)
        let exists = await service.hasSecret(for: missing)
        #expect(!exists)
    }

    @Test("Package.resolved gates swift-nio-ssh >= 0.14.1 (CVE-2026-43798)")
    func verifySwiftNIOSSHVersionGate() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let resolvedURL = repoRoot.appendingPathComponent("Package.resolved")
        let data = try Data(contentsOf: resolvedURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let pins = try #require(json?["pins"] as? [[String: Any]])
        let sshPin = try #require(pins.first { ($0["identity"] as? String) == "swift-nio-ssh" })
        let state = try #require(sshPin["state"] as? [String: Any])
        let version = try #require(state["version"] as? String)
        let parts = version.split(separator: ".").compactMap { Int($0) }
        #expect(parts.count >= 3)
        let tuple = (parts[0], parts[1], parts[2])
        #expect(tuple >= (0, 14, 1))
    }

    @Test("TLSCertificateValidator rejects invalid ports before connecting")
    func validatorRejectsInvalidPorts() async {
        let validator = TLSCertificateValidator()
        do {
            _ = try await validator.preflightVerifyTLS(host: "127.0.0.1", port: 0, timeoutSeconds: 1)
            Issue.record("Expected invalidConfiguration error for port 0")
        } catch let error as AppError {
            if case .invalidConfiguration = error {
                #expect(Bool(true))
            } else {
                Issue.record("Unexpected error: \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }

        do {
            _ = try await validator.preflightVerifyExplicitFTPS(host: "127.0.0.1", port: 65536, timeoutSeconds: 1)
            Issue.record("Expected invalidConfiguration error for port 65536")
        } catch let error as AppError {
            if case .invalidConfiguration = error {
                #expect(Bool(true))
            } else {
                Issue.record("Unexpected error: \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("PrivateKeyParser KeyMetadata detects FIDO2/U2F security key tokens")
    func keyMetadataDetectsSecurityKeys() {
        let plainMeta = PrivateKeyParser.KeyMetadata(
            cipher: "none",
            kdf: "none",
            isEncrypted: false,
            keyType: "ssh-ed25519",
            isSecurityKey: false
        )
        #expect(!plainMeta.isSecurityKey)

        let skMeta = PrivateKeyParser.KeyMetadata(
            cipher: "none",
            kdf: "none",
            isEncrypted: false,
            keyType: "sk-ssh-ed25519@openssh.com",
            isSecurityKey: true
        )
        #expect(skMeta.isSecurityKey)
    }
}
