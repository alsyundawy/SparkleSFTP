import CommonCrypto
import CryptoKit
import Foundation
import SparkleCore

/// Cryptographic operations for SparkleSFTP v0.6.0 portable configuration bundles & vaults.
public enum ConfigBundleCrypto {
    public static let defaultIterations: UInt32 = 600_000
    public static let saltByteCount = 16
    public static let nonceByteCount = 12
    public static let keyByteCount = 32 // 256 bits
    public static let tagByteCount = 16

    /// Derives an AES-256-GCM symmetric key using PBKDF2-HMAC-SHA256 with memory zeroization.
    public static func deriveKey(
        passphrase: String,
        salt: Data,
        iterations: UInt32 = defaultIterations
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
        let key = SymmetricKey(data: derivedKeyData)
        // Zeroize intermediate key buffer
        derivedKeyData.resetBytes(in: 0 ..< derivedKeyData.count)
        return key
    }

    /// Encrypts raw bundle JSON into authenticated binary `.sparklevault` format (Format B).
    public static func encryptVault(
        bundleData: Data,
        passphrase: String,
        iterations: UInt32 = defaultIterations
    ) throws -> Data {
        guard bundleData.count <= SparkleConfigBundle.maxFileSizeBytes else {
            throw AppError.persistenceFailure(reason: "Payload exceeds 25 MB vault capacity limit")
        }

        var saltBytes = [UInt8](repeating: 0, count: saltByteCount)
        guard SecRandomCopyBytes(kSecRandomDefault, saltByteCount, &saltBytes) == errSecSuccess else {
            throw AppError.persistenceFailure(reason: "Failed to generate cryptographically random salt")
        }
        let salt = Data(saltBytes)

        var nonceBytes = [UInt8](repeating: 0, count: nonceByteCount)
        guard SecRandomCopyBytes(kSecRandomDefault, nonceByteCount, &nonceBytes) == errSecSuccess else {
            throw AppError.persistenceFailure(reason: "Failed to generate cryptographically random nonce")
        }
        let nonce = Data(nonceBytes)

        let header = SparkleVaultHeader(
            iterations: iterations,
            salt: salt,
            nonce: nonce,
            ciphertextLength: UInt32(bundleData.count)
        )
        let headerData = header.serialize()

        let symmetricKey = try deriveKey(passphrase: passphrase, salt: salt, iterations: iterations)
        let gcmNonce = try AES.GCM.Nonce(data: nonce)
        let sealedBox = try AES.GCM.seal(
            bundleData,
            using: symmetricKey,
            nonce: gcmNonce,
            authenticating: headerData
        )

        var vaultData = Data()
        vaultData.append(headerData)
        vaultData.append(sealedBox.ciphertext)
        vaultData.append(sealedBox.tag)
        return vaultData
    }

    /// Decrypts an authenticated binary `.sparklevault` format (Format B) or legacy encrypted archive.
    public static func decryptVault(
        vaultData: Data,
        passphrase: String
    ) throws -> Data {
        guard vaultData.count <= SparkleConfigBundle.maxFileSizeBytes else {
            throw AppError.persistenceFailure(reason: "Vault file exceeds 25 MB safety limit")
        }

        // Check if file starts with binary SPKVAULT1 header
        if vaultData.count >= SparkleVaultHeader.headerLength,
           vaultData.prefix(9) == Data(SparkleVaultHeader.magicASCII.utf8) {
            let header = try SparkleVaultHeader.parse(from: vaultData)
            let headerData = vaultData.prefix(SparkleVaultHeader.headerLength)
            let expectedTotalLength = SparkleVaultHeader.headerLength + Int(header.ciphertextLength) + tagByteCount
            guard vaultData.count == expectedTotalLength else {
                // Fail-closed generic error
                throw AppError.persistenceFailure(reason: "Cannot decrypt: invalid passphrase or corrupted vault file")
            }

            let ciphertext = vaultData.subdata(
                in: SparkleVaultHeader.headerLength ..< SparkleVaultHeader.headerLength + Int(header.ciphertextLength)
            )
            let tag = vaultData.suffix(tagByteCount)

            do {
                let symmetricKey = try deriveKey(
                    passphrase: passphrase,
                    salt: header.salt,
                    iterations: header.iterations
                )
                let gcmNonce = try AES.GCM.Nonce(data: header.nonce)
                let sealedBox = try AES.GCM.SealedBox(nonce: gcmNonce, ciphertext: ciphertext, tag: tag)
                return try AES.GCM.open(sealedBox, using: symmetricKey, authenticating: headerData)
            } catch {
                // Fail-closed without oracle leakage
                throw AppError.persistenceFailure(reason: "Cannot decrypt: invalid passphrase or corrupted vault file")
            }
        }

        // Fallback for legacy JSON archive format
        if let jsonString = String(data: vaultData, encoding: .utf8),
           jsonString.contains(SparkleSFTPEncryptedArchive.formatIdentifier) {
            let decoder = JSONDecoder()
            guard let archive = try? decoder.decode(SparkleSFTPEncryptedArchive.self, from: vaultData) else {
                throw AppError.persistenceFailure(reason: "Cannot decrypt: invalid passphrase or corrupted archive")
            }
            return try InternalConnectionExporter.decrypt(archive: archive, passphrase: passphrase)
        }

        throw AppError.persistenceFailure(reason: "Unrecognized vault or encrypted bundle format")
    }

    /// Calculates SHA-256 integrity digest over canonical JSON representation of bundle payload.
    public static func computeIntegrity(payload: ConfigBundlePayload) throws -> ConfigBundleIntegrity {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let payloadData = try encoder.encode(payload)
        let digest = SHA256.hash(data: payloadData)
        let hexString = digest.compactMap { String(format: "%02x", $0) }.joined()
        return ConfigBundleIntegrity(alg: "sha256", digest: hexString)
    }

    /// Validates SHA-256 integrity digest of a config bundle.
    public static func verifyIntegrity(bundle: SparkleConfigBundle) -> Bool {
        guard let computed = try? computeIntegrity(payload: bundle.payload) else {
            return false
        }
        return computed.digest.caseInsensitiveCompare(bundle.integrity.digest) == .orderedSame
    }
}
