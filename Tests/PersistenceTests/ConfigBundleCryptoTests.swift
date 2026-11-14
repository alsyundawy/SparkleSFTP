import Foundation
import SparkleCore
@testable import SparklePersistence
import Testing

@Suite("Config Bundle Crypto & Vault Format B Tests")
struct ConfigBundleCryptoTests {
    @Test("Vault encryption and decryption roundtrip preserves exact bundle data")
    func vaultEncryptionRoundtrip() throws {
        let payload = ConfigBundlePayload(
            profiles: [
                ConnectionProfile(
                    name: "Vault Test Node",
                    host: "vault.example.com",
                    port: 22,
                    username: "admin"
                )
            ]
        )
        let integrity = try ConfigBundleCrypto.computeIntegrity(payload: payload)
        let bundle = SparkleConfigBundle(payload: payload, integrity: integrity)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let plaintextData = try encoder.encode(bundle)

        let passphrase = "Correct-Horse-Battery-Staple-2026!"
        let vaultData = try ConfigBundleCrypto.encryptVault(bundleData: plaintextData, passphrase: passphrase)

        // Verify header
        #expect(vaultData.count > SparkleVaultHeader.headerLength)
        let header = try SparkleVaultHeader.parse(from: vaultData)
        #expect(header.kdfId == SparkleVaultHeader.kdfPBKDF2HMACSHA256)
        #expect(header.iterations == SparkleVaultHeader.defaultIterations)

        // Decrypt with correct passphrase
        let decryptedData = try ConfigBundleCrypto.decryptVault(vaultData: vaultData, passphrase: passphrase)
        #expect(decryptedData == plaintextData)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decodedBundle = try decoder.decode(SparkleConfigBundle.self, from: decryptedData)
        #expect(decodedBundle.payload.profiles.count == 1)
        #expect(decodedBundle.payload.profiles.first?.host == "vault.example.com")
        #expect(ConfigBundleCrypto.verifyIntegrity(bundle: decodedBundle))
    }

    @Test("Tampered ciphertext or incorrect password throws authentication error")
    func vaultTamperResistance() throws {
        let sampleData = Data("sample-secret-payload".utf8)
        let passphrase = "Master-Vault-Password-99!"
        var vaultData = try ConfigBundleCrypto.encryptVault(bundleData: sampleData, passphrase: passphrase)

        // Wrong passphrase
        #expect(throws: Error.self) {
            _ = try ConfigBundleCrypto.decryptVault(vaultData: vaultData, passphrase: "Wrong-Password-123!")
        }

        // Tamper ciphertext byte
        let lastByteIdx = vaultData.count - 1
        vaultData[lastByteIdx] ^= 0xFF
        #expect(throws: Error.self) {
            _ = try ConfigBundleCrypto.decryptVault(vaultData: vaultData, passphrase: passphrase)
        }
    }
}
