import Foundation
import SparkleCore

extension ConfigImporter {
    /// Loads and parses a `SparkleConfigBundle` from raw data.
    public static func loadBundle(
        data: Data,
        filename: String = "",
        passphrase: String? = nil
    ) throws -> (bundle: SparkleConfigBundle, format: ConfigSourceFormat) {
        guard data.count <= SparkleConfigBundle.maxFileSizeBytes else {
            throw AppError.persistenceFailure(reason: "File exceeds 25 MB safety limit (CWE-400)")
        }

        let format = detectFormat(data: data, filename: filename)
        switch format {
        case .sparkleVault:
            return try (loadVault(data: data, passphrase: passphrase), .sparkleVault)
        case .sparkleConfig:
            return try (loadPlaintext(data: data), .sparkleConfig)
        case .legacyExport:
            return try (loadLegacy(data: data), .legacyExport)
        case .fileZillaXML:
            return try (loadFileZilla(data: data), .fileZillaXML)
        case .winSCPINI:
            return try (loadWinSCP(data: data), .winSCPINI)
        case .openSSHConfig:
            return try (loadOpenSSH(data: data), .openSSHConfig)
        case .unknown:
            let message = "Unrecognized file format. " +
                "Supported: .sparkleconfig, .sparklevault, .xml, .ini, and ~/.ssh/config"
            throw AppError.persistenceFailure(reason: message)
        }
    }

    private static func loadVault(data: Data, passphrase: String?) throws -> SparkleConfigBundle {
        guard let pass = passphrase, !pass.isEmpty else {
            throw AppError.persistenceFailure(reason: "Passphrase required to decrypt encrypted vault")
        }
        let plaintextData = try ConfigBundleCrypto.decryptVault(vaultData: data, passphrase: pass)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SparkleConfigBundle.self, from: plaintextData)
    }

    private static func loadPlaintext(data: Data) throws -> SparkleConfigBundle {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SparkleConfigBundle.self, from: data)
    }

    private static func loadLegacy(data: Data) throws -> SparkleConfigBundle {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let legacy = try decoder.decode(SparkleSFTPConnectionExport.self, from: data)
        let profiles = legacy.connections.map(\.profile)
        let payload = ConfigBundlePayload(profiles: profiles, groups: legacy.groups)
        let integrity = try ConfigBundleCrypto.computeIntegrity(payload: payload)
        return SparkleConfigBundle(
            magic: SparkleConfigBundle.currentMagic,
            schemaVersion: 1,
            kind: "connections",
            appVersion: legacy.appVersion,
            createdAt: legacy.exportedAt,
            payload: payload,
            integrity: integrity
        )
    }

    private static func loadFileZilla(data: Data) throws -> SparkleConfigBundle {
        let imported = try FileZillaImporter.parse(xmlData: data)
        let profiles = imported.map(\.profile)
        let payload = ConfigBundlePayload(profiles: profiles)
        let integrity = try ConfigBundleCrypto.computeIntegrity(payload: payload)
        return SparkleConfigBundle(
            magic: SparkleConfigBundle.currentMagic,
            schemaVersion: 1,
            kind: "imported-filezilla",
            appVersion: "0.6.0",
            createdAt: Date(),
            payload: payload,
            integrity: integrity
        )
    }

    private static func loadWinSCP(data: Data) throws -> SparkleConfigBundle {
        guard let iniString = String(data: data, encoding: .utf8) ??
            String(data: data, encoding: .windowsCP1252)
        else {
            throw AppError.persistenceFailure(reason: "Malformed text encoding in WinSCP INI")
        }
        let imported = IniSessionImporter.parse(iniContents: iniString)
        let profiles = imported.map(\.profile)
        let payload = ConfigBundlePayload(profiles: profiles)
        let integrity = try ConfigBundleCrypto.computeIntegrity(payload: payload)
        return SparkleConfigBundle(
            magic: SparkleConfigBundle.currentMagic,
            schemaVersion: 1,
            kind: "imported-winscp",
            appVersion: "0.6.0",
            createdAt: Date(),
            payload: payload,
            integrity: integrity
        )
    }

    private static func loadOpenSSH(data: Data) throws -> SparkleConfigBundle {
        guard let configString = String(data: data, encoding: .utf8) else {
            throw AppError.persistenceFailure(reason: "Malformed UTF-8 in OpenSSH config")
        }
        let hostEntries = SSHConfigParser.parse(contents: configString)
        let profiles = hostEntries.map { $0.toConnectionProfile() }
        let payload = ConfigBundlePayload(profiles: profiles)
        let integrity = try ConfigBundleCrypto.computeIntegrity(payload: payload)
        return SparkleConfigBundle(
            magic: SparkleConfigBundle.currentMagic,
            schemaVersion: 1,
            kind: "imported-openssh",
            appVersion: "0.6.0",
            createdAt: Date(),
            payload: payload,
            integrity: integrity
        )
    }
}
