import CommonCrypto
import CryptoKit
import Foundation
import SparkleCore

/// High-performance, cryptographically secure exporter and importer for SparkleSFTP connections.
public enum InternalConnectionExporter {
    public static let pbkdf2Iterations: UInt32 = 100_000
    public static let saltByteCount = 16
    public static let keyByteCount = 32 // 256 bits

    /// Derives a 256-bit AES-GCM symmetric key using PBKDF2-HMAC-SHA256.
    public static func deriveKey(
        passphrase: String,
        salt: Data,
        iterations: UInt32 = pbkdf2Iterations
    ) throws -> SymmetricKey {
        guard let passData = passphrase.data(using: .utf8), !passData.isEmpty else {
            throw AppError.persistenceFailure(reason: "Passphrase cannot be empty")
        }
        var derivedKeyData = Data(count: keyByteCount)
        let status = derivedKeyData.withUnsafeMutableBytes { derivedKeyBytes in
            salt.withUnsafeBytes { saltBytes in
                passData.withUnsafeBytes { passBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passBytes.baseAddress?.assumingMemoryBound(to: Int8.self),
                        passData.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        iterations,
                        derivedKeyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        keyByteCount
                    )
                }
            }
        }
        guard status == kCCSuccess else {
            throw AppError.persistenceFailure(reason: "PBKDF2 key derivation failed with code \(status)")
        }
        return SymmetricKey(data: derivedKeyData)
    }

    /// Encrypts plaintext payload using AES-256-GCM with a fresh random 16-byte salt and 12-byte nonce.
    public static func encrypt(data: Data, passphrase: String) throws -> SparkleSFTPEncryptedArchive {
        var saltBytes = [UInt8](repeating: 0, count: saltByteCount)
        guard SecRandomCopyBytes(kSecRandomDefault, saltByteCount, &saltBytes) == errSecSuccess else {
            throw AppError.persistenceFailure(reason: "Failed to generate cryptographically secure salt")
        }
        let salt = Data(saltBytes)
        let symmetricKey = try deriveKey(passphrase: passphrase, salt: salt)
        let sealedBox = try AES.GCM.seal(data, using: symmetricKey)
        let nonceData = Data(sealedBox.nonce)
        let tagData = sealedBox.tag

        return SparkleSFTPEncryptedArchive(
            saltBase64: salt.base64EncodedString(),
            nonceBase64: nonceData.base64EncodedString(),
            tagBase64: tagData.base64EncodedString(),
            ciphertextBase64: sealedBox.ciphertext.base64EncodedString()
        )
    }

    /// Decrypts a `SparkleSFTPEncryptedArchive` using the provided passphrase.
    public static func decrypt(archive: SparkleSFTPEncryptedArchive, passphrase: String) throws -> Data {
        guard archive.format == SparkleSFTPEncryptedArchive.formatIdentifier else {
            throw AppError.persistenceFailure(reason: "Invalid archive format identifier: \(archive.format)")
        }
        guard let salt = Data(base64Encoded: archive.saltBase64),
              let nonceData = Data(base64Encoded: archive.nonceBase64),
              let tag = Data(base64Encoded: archive.tagBase64),
              let ciphertext = Data(base64Encoded: archive.ciphertextBase64)
        else {
            throw AppError.persistenceFailure(reason: "Malformed base64 components in encrypted archive")
        }
        let symmetricKey = try deriveKey(
            passphrase: passphrase,
            salt: salt,
            iterations: UInt32(max(10000, archive.iterations))
        )
        let nonce = try AES.GCM.Nonce(data: nonceData)
        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
        do {
            return try AES.GCM.open(sealedBox, using: symmetricKey)
        } catch {
            throw AppError.persistenceFailure(
                reason: "Decryption failed: invalid passphrase or tampered archive"
            )
        }
    }

    /// Assembles an unencrypted `SparkleSFTPConnectionExport` struct.
    public static func buildExport(
        profiles: [ConnectionProfile],
        groups: [ServerGroup],
        credentialStore: CredentialStoreProtocol?,
        mode: ConnectionExportSecurityMode
    ) async throws -> SparkleSFTPConnectionExport {
        let groupMap = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0.name) })
        var exportedConnections: [ExportedConnection] = []

        for profile in profiles {
            var sanitizedProfile = profile
            var embeddedSecretBase64: String?
            var embeddedSecretKind: String?

            switch mode {
            case .sanitizedWithoutSecrets:
                sanitizedProfile.passwordRef = nil
                sanitizedProfile.privateKeyRef = nil
                sanitizedProfile.passphraseRef = nil
            case .passwordProtected, .plaintextSecrets:
                if let ref = profile.passwordRef, let store = credentialStore {
                    if let secretData = try? await store.loadSecret(for: ref, prompt: nil) {
                        embeddedSecretBase64 = secretData.base64EncodedString()
                        embeddedSecretKind = "password"
                    }
                } else if let ref = profile.privateKeyRef, let store = credentialStore {
                    if let secretData = try? await store.loadSecret(for: ref, prompt: nil) {
                        embeddedSecretBase64 = secretData.base64EncodedString()
                        embeddedSecretKind = "privateKey"
                    }
                }
            }

            let groupName = profile.groupID.flatMap { groupMap[$0] }
            exportedConnections.append(
                ExportedConnection(
                    profile: sanitizedProfile,
                    groupName: groupName,
                    embeddedSecretBase64: embeddedSecretBase64,
                    embeddedSecretKind: embeddedSecretKind
                )
            )
        }

        return SparkleSFTPConnectionExport(
            groups: groups,
            connections: exportedConnections
        )
    }

    /// Exports connection profiles and groups to Data ready for saving to a file.
    public static func exportData(
        profiles: [ConnectionProfile],
        groups: [ServerGroup],
        credentialStore: CredentialStoreProtocol?,
        mode: ConnectionExportSecurityMode,
        passphrase: String? = nil
    ) async throws -> Data {
        let exportObj = try await buildExport(
            profiles: profiles,
            groups: groups,
            credentialStore: credentialStore,
            mode: mode
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let plainJSON = try encoder.encode(exportObj)

        if mode == .passwordProtected {
            guard let pass = passphrase, !pass.isEmpty else {
                throw AppError.persistenceFailure(reason: "Passphrase required for password-protected export")
            }
            let archive = try encrypt(data: plainJSON, passphrase: pass)
            return try encoder.encode(archive)
        }
        return plainJSON
    }

    /// Fast inspect to detect if JSON data is an encrypted SparkleSFTP archive.
    public static func isEncryptedArchive(data: Data) -> Bool {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let format = json["format"] as? String,
           format == SparkleSFTPEncryptedArchive.formatIdentifier {
            return true
        }
        return false
    }

    /// Fast inspect to detect if JSON data is a native SparkleSFTP unencrypted export.
    public static func isNativeExport(data: Data) -> Bool {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let gen = json["generator"] as? String,
           gen.contains("SparkleSFTP") {
            return true
        }
        return false
    }

    /// Parses native JSON or decrypted archive data into an `ExternalImportReport`.
    public static func parseToReport(data: Data, passphrase: String? = nil) throws -> ExternalImportReport {
        var rawData = data
        if isEncryptedArchive(data: rawData) {
            guard let passphrase, !passphrase.isEmpty else {
                throw AppError.persistenceFailure(reason: "ARCHIVE_ENCRYPTED_PASSPHRASE_REQUIRED")
            }
            let decoder = JSONDecoder()
            let archive = try decoder.decode(SparkleSFTPEncryptedArchive.self, from: rawData)
            rawData = try decrypt(archive: archive, passphrase: passphrase)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let exportObj = try decoder.decode(SparkleSFTPConnectionExport.self, from: rawData)

        var imported: [ImportedConnection] = []
        for item in exportObj.connections {
            let secretData = item.embeddedSecretBase64.flatMap { Data(base64Encoded: $0) }
            let status: ImportedSecretStatus = secretData != nil ? .plaintextReady : .none
            imported.append(
                ImportedConnection(
                    profile: item.profile,
                    transientSecret: secretData,
                    groupName: item.groupName,
                    secretStatus: status,
                    notes: "Imported from SparkleSFTP backup (\(exportObj.appVersion))"
                )
            )
        }

        return ExternalImportReport(
            format: .nativeJSON,
            connections: imported,
            skippedUnsupported: 0,
            warnings: []
        )
    }
}
