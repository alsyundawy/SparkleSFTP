import Crypto
import Foundation
import NIOSSH
import Security
import SparkleCore
@testable import SparkleSecurity
import Testing

actor InMemoryHostTrustBacking: HostTrustBackingStore {
    private var blob: Data?
    private let corruptNextRead: Bool

    init(corruptNextRead: Bool = false) {
        self.corruptNextRead = corruptNextRead
    }

    func loadTrustBlob() async throws -> Data? {
        if corruptNextRead {
            return Data("not-json".utf8)
        }
        return blob
    }

    func saveTrustBlob(_ data: Data) async throws {
        blob = data
    }
}

@Suite("SparkleSecurity Tests")
struct SecurityTests {
    @Test("Keychain attributes strictly enforce WhenUnlockedThisDeviceOnly and disable sync")
    func keychainAttributesEnforceDeviceIsolation() throws {
        let keychain = KeychainService(serviceIdentifier: "com.alsyundawy.SparkleSFTP.test")
        let attrs = try keychain.buildAddAttributes(
            data: Data("s3cr3t".utf8),
            accountKey: "password:test",
            requireTouchID: false
        )
        let accessible = attrs[kSecAttrAccessible as String] as? String
        #expect(accessible == (kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String))
        let syncFlag = attrs[kSecAttrSynchronizable as String] as? Bool
        #expect(syncFlag == false)
    }

    @Test("HostTrustStore enforces 6-state TOFU lifecycle and blocks host key mismatches")
    func hostTrustLifecycle() async throws {
        let backing = InMemoryHostTrustBacking()
        let store = HostTrustStore(backingStore: backing)

        #expect(await store.state(forHost: "prod.example.com", port: 22) == .unknown)

        let pending = await store.evaluate(host: "prod.example.com", port: 22, fingerprint: "SHA256:abc123")
        #expect(pending == .pendingUserDecision(fingerprint: "SHA256:abc123"))

        try await store.trust(host: "prod.example.com", port: 22, fingerprint: "SHA256:abc123")
        let trusted = await store.evaluate(host: "prod.example.com", port: 22, fingerprint: "SHA256:abc123")
        if case let .trusted(fingerprint, _) = trusted {
            #expect(fingerprint == "SHA256:abc123")
        } else {
            Issue.record("Expected trusted state")
        }

        let mismatch = await store.evaluate(host: "prod.example.com", port: 22, fingerprint: "SHA256:evil999")
        #expect(mismatch == .mismatch(expected: "SHA256:abc123", got: "SHA256:evil999"))

        try await store.reject(host: "rogue.example.com", port: 22)
        #expect(await store.state(forHost: "rogue.example.com", port: 22) == .rejected)
    }

    @Test("HostTrustStore detects corrupted persisted trust payload")
    func hostTrustDetectsCorruption() async {
        let backing = InMemoryHostTrustBacking(corruptNextRead: true)
        let store = HostTrustStore(backingStore: backing)
        #expect(await store.state(forHost: "any.example.com", port: 22) == .corrupted)
    }

    @Test("PathValidator blocks CWE-22 path traversal and CWE-59 symlink escapes")
    func pathValidatorBlocksTraversalAndSymlinks() throws {
        let baseRemote = RemotePath(rawValue: "/var/www/app")
        #expect(throws: AppError.pathTraversal(attempted: "../../etc/passwd")) {
            _ = try PathValidator.canonicalizeRemote("../../etc/passwd", relativeTo: baseRemote)
        }
        let validRemote = try PathValidator.canonicalizeRemote("assets/logo.png", relativeTo: baseRemote)
        #expect(validRemote.rawValue == "/var/www/app/assets/logo.png")

        let baseLocal = FileManager.default.temporaryDirectory.appendingPathComponent("SparklePathTest-\(UUID())")
        try FileManager.default.createDirectory(at: baseLocal, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: baseLocal) }

        #expect(throws: AppError.pathTraversal(attempted: "../id_rsa")) {
            _ = try PathValidator.safeLocalDestination(filename: "../id_rsa", baseDirectory: baseLocal)
        }
        #expect(throws: AppError.maliciousSymlink(target: "../../.ssh/authorized_keys")) {
            _ = try PathValidator.safeLocalDestination(
                filename: "keylink",
                baseDirectory: baseLocal,
                symlinkTarget: "../../.ssh/authorized_keys"
            )
        }
        let okURL = try PathValidator.safeLocalDestination(filename: "report.pdf", baseDirectory: baseLocal)
        #expect(okURL.lastPathComponent == "report.pdf")
    }

    @Test("PrivateKeyParser parses real OpenSSH Ed25519 key and produces SHA256 fingerprint")
    func privateKeyParserAndFingerprint() throws {
        // Generate an ephemeral real Ed25519 private key via Crypto and encode minimal OpenSSH v1 container
        let signingKey = Curve25519.Signing.PrivateKey()
        let pubRaw = signingKey.publicKey.rawRepresentation
        let privSeedAndPub = signingKey.rawRepresentation + pubRaw

        let pem = buildTestOpenSSHEd25519PEM(publicRaw: pubRaw, privateSeedAndPub: privSeedAndPub)
        let parsed = try PrivateKeyParser.parsePrivateKey(pemString: pem)
        let fingerprint = SSHKeyFingerprint.sha256(for: parsed.publicKey)
        #expect(fingerprint.hasPrefix("SHA256:"))
        #expect(SSHKeyFingerprint.keyAlgorithm(for: parsed.publicKey) == "ssh-ed25519")
    }

    private func buildTestOpenSSHEd25519PEM(publicRaw: Data, privateSeedAndPub: Data) -> String {
        func sshString(_ data: Data) -> Data {
            var len = UInt32(data.count).bigEndian
            return Data(bytes: &len, count: 4) + data
        }
        func sshString(_ str: String) -> Data {
            sshString(Data(str.utf8))
        }

        let pubKeyBlob = sshString("ssh-ed25519") + sshString(publicRaw)
        var privPayload = Data([0x11, 0x22, 0x33, 0x44, 0x11, 0x22, 0x33, 0x44])
        privPayload += sshString("ssh-ed25519")
        privPayload += sshString(publicRaw)
        privPayload += sshString(privateSeedAndPub)
        privPayload += sshString("test")
        while privPayload.count % 8 != 0 {
            privPayload.append(UInt8(privPayload.count % 8))
        }

        var container = Data("openssh-key-v1\0".utf8)
        container += sshString("none")
        container += sshString("none")
        container += sshString(Data())
        var count = UInt32(1).bigEndian
        container += Data(bytes: &count, count: 4)
        container += sshString(pubKeyBlob)
        container += sshString(privPayload)

        let b64 = container.base64EncodedString()
        return "-----BEGIN OPENSSH PRIVATE KEY-----\n\(b64)\n-----END OPENSSH PRIVATE KEY-----"
    }

    @Test("TLSCertificateValidator rejects self-signed untrusted X.509 certificate (TASK-117)")
    func tlsValidatorRejectsUntrustedCertificate() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SparkleCert-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let keyPath = dir.appendingPathComponent("key.pem").path
        let derURL = dir.appendingPathComponent("cert.der")
        let openssl = FileManager.default.fileExists(atPath: "/usr/local/opt/openssl@3/bin/openssl")
            ? "/usr/local/opt/openssl@3/bin/openssl"
            : "/usr/bin/openssl"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: openssl)
        process.arguments = [
            "req", "-x509", "-newkey", "rsa:2048", "-nodes",
            "-keyout", keyPath, "-out", derURL.path, "-outform", "DER",
            "-days", "1", "-subj", "/CN=selfsigned.invalid"
        ]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)

        let derData = try Data(contentsOf: derURL)
        let cert = try #require(SecCertificateCreateWithData(nil, derData as CFData))
        var optionalTrust: SecTrust?
        let policy = SecPolicyCreateSSL(true, "prod.example.com" as CFString)
        let status = SecTrustCreateWithCertificates([cert] as CFArray, policy, &optionalTrust)
        #expect(status == errSecSuccess)
        let trust = try #require(optionalTrust)

        let validator = TLSCertificateValidator()
        var threwTLSFailure = false
        do {
            _ = try validator.validateServerCertificate(trust, host: "prod.example.com")
        } catch AppError.tlsValidationFailed {
            threwTLSFailure = true
        }
        #expect(threwTLSFailure)
    }

    @Test("PathValidator rejects pre-existing local symlink at destination (CWE-59)")
    func pathValidatorRejectsExistingDestinationSymlink() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SparkleSymDest-\(UUID())")
        let outsideFile = FileManager.default.temporaryDirectory.appendingPathComponent("outside-\(UUID()).txt")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("sensitive".utf8).write(to: outsideFile)
        defer {
            try? FileManager.default.removeItem(at: dir)
            try? FileManager.default.removeItem(at: outsideFile)
        }

        let linkDest = dir.appendingPathComponent("trap.txt")
        try FileManager.default.createSymbolicLink(at: linkDest, withDestinationURL: outsideFile)
        let expectedDest = dir.standardizedFileURL.resolvingSymlinksInPath()
            .appendingPathComponent("trap.txt", isDirectory: false).path
        #expect(throws: AppError.symlinkTraversal(destination: expectedDest)) {
            _ = try PathValidator.safeLocalDestination(filename: "trap.txt", baseDirectory: dir)
        }
    }

    @Test("UpdateConfigurationValidator rejects placeholder SUPublicEDKey and non-HTTPS feeds (SEC-006)")
    func updateConfigurationValidatorEnforcesSignedHTTPS() {
        #expect(!UpdateConfigurationValidator.isValidHTTPSFeed("http://example.com/appcast.xml"))
        #expect(UpdateConfigurationValidator
            .isValidHTTPSFeed("https://github.com/alsyundawy/SparkleSFTP/releases/latest/download/appcast.xml"))
        #expect(!UpdateConfigurationValidator.isValidEd25519PublicKey("REPLACE_WITH_PRODUCTION_ED25519_PUBLIC_KEY"))
        #expect(!UpdateConfigurationValidator.isValidEd25519PublicKey("short"))
        let validKey = Data(repeating: 0xAB, count: 32).base64EncodedString()
        #expect(UpdateConfigurationValidator.isValidEd25519PublicKey(validKey))
    }
}
