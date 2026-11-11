import Foundation

/// Structured JSON document schema for maintainable UI translations (`Resources/Locales/*.json`).
public struct LocaleDocument: Sendable, Codable, Equatable, Identifiable {
    public let code: String
    public let displayName: String
    public let version: String
    public let strings: [String: String]

    public var id: String {
        code
    }

    public init(code: String, displayName: String, version: String = "0.3.0", strings: [String: String]) {
        self.code = code
        self.displayName = displayName
        self.version = version
        self.strings = strings
    }
}

/// Manages built-in bundled locales (`en.json`, `id.json`) plus runtime user/maintainer JSON overrides.
public enum LocalizationCatalog {
    public static var customLocalesDirectoryURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return appSupport
            .appendingPathComponent("SparkleSFTP", isDirectory: true)
            .appendingPathComponent("Locales", isDirectory: true)
    }

    public static func loadBundledStrings(code: String) -> [String: String] {
        guard let bundle = resolveResourceBundle() else {
            return fallbackStrings(code: code)
        }
        let candidateURL = bundle.url(forResource: code, withExtension: "json", subdirectory: "Locales")
            ?? bundle.url(forResource: code, withExtension: "json")
        guard let url = candidateURL,
              let data = try? Data(contentsOf: url),
              let doc = decodeLocaleData(data, fallbackCode: code)
        else {
            return fallbackStrings(code: code)
        }
        return fallbackStrings(code: code).merging(doc.strings) { _, bundled in bundled }
    }

    static func resolveResourceBundle() -> Bundle? {
        let bundleFilename = "SparkleSFTP_SparkleDesignSystem.bundle"
        let candidates: [URL?] = [
            Bundle.main.resourceURL?.appendingPathComponent(bundleFilename),
            Bundle.main.bundleURL.appendingPathComponent(bundleFilename)
        ]
        for candidate in candidates.compactMap(\.self) where FileManager.default.fileExists(atPath: candidate.path) {
            if let loaded = Bundle(url: candidate) {
                return loaded
            }
        }
        guard Bundle.main.bundleURL.pathExtension != "app" else {
            return nil
        }
        return Bundle.module
    }

    public static func loadAvailableLocales(
        customDirectory: URL = customLocalesDirectoryURL
    ) -> [LocaleDocument] {
        var map: [String: LocaleDocument] = [
            "en": LocaleDocument(code: "en", displayName: "English", strings: loadBundledStrings(code: "en")),
            "id": LocaleDocument(code: "id", displayName: "Bahasa Indonesia", strings: loadBundledStrings(code: "id"))
        ]

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: customDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return Array(map.values).sorted { $0.code < $1.code }
        }

        for fileURL in files where fileURL.pathExtension.lowercased() == "json" {
            let stem = fileURL.deletingPathExtension().lastPathComponent
            guard let data = try? Data(contentsOf: fileURL),
                  let custom = decodeLocaleData(data, fallbackCode: stem)
            else {
                continue
            }
            let base = map[custom.code]?.strings ?? [:]
            let merged = base.merging(custom.strings) { _, overrideVal in overrideVal }
            map[custom.code] = LocaleDocument(
                code: custom.code,
                displayName: custom.displayName,
                version: custom.version,
                strings: merged
            )
        }

        return Array(map.values).sorted { $0.code < $1.code }
    }

    public static func importLocaleFile(
        from sourceURL: URL,
        into directory: URL = customLocalesDirectoryURL
    ) throws -> LocaleDocument {
        let didScope = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didScope {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }
        let data = try Data(contentsOf: sourceURL)
        let stem = sourceURL.deletingPathExtension().lastPathComponent
        guard let parsed = decodeLocaleData(data, fallbackCode: stem),
              !parsed.strings.isEmpty,
              isSafeLocaleCode(parsed.code)
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destURL = directory.appendingPathComponent("\(parsed.code).json", isDirectory: false)
        let resolvedDir = directory.standardizedFileURL.resolvingSymlinksInPath()
        let resolvedDest = destURL.standardizedFileURL
        let prefix = resolvedDir.path.hasSuffix("/") ? resolvedDir.path : resolvedDir.path + "/"
        guard resolvedDest.path.hasPrefix(prefix) else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        try exportLocaleDocument(parsed, to: resolvedDest)
        return parsed
    }

    private static func isSafeLocaleCode(_ code: String) -> Bool {
        !code.isEmpty
            && code.count <= 32
            && code != "."
            && code != ".."
            && code.unicodeScalars.allSatisfy { scalar in
                CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_"
            }
    }

    public static func exportLocaleDocument(_ document: LocaleDocument, to destinationURL: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        try data.write(to: destinationURL, options: [.atomic])
    }

    public static func missingKeys(for document: LocaleDocument, referenceKeys: Set<String>? = nil) -> [String] {
        let baseline = referenceKeys ?? Set(loadBundledStrings(code: "en").keys)
        return baseline.subtracting(document.strings.keys).sorted()
    }

    public static func coveragePercentage(for document: LocaleDocument, referenceKeys: Set<String>? = nil) -> Double {
        let baseline = referenceKeys ?? Set(loadBundledStrings(code: "en").keys)
        guard !baseline.isEmpty else { return 100.0 }
        let matched = baseline.intersection(document.strings.keys).count
        return (Double(matched) / Double(baseline.count)) * 100.0
    }

    static func decodeLocaleData(_ data: Data, fallbackCode: String) -> LocaleDocument? {
        let decoder = JSONDecoder()
        if let doc = try? decoder.decode(LocaleDocument.self, from: data), !doc.strings.isEmpty {
            return doc
        }
        if let rawDict = try? decoder.decode([String: String].self, from: data), !rawDict.isEmpty {
            return LocaleDocument(
                code: fallbackCode,
                displayName: fallbackCode.uppercased(),
                strings: rawDict
            )
        }
        return nil
    }

    private static func fallbackStrings(code: String) -> [String: String] {
        let isID = code.lowercased() == "id"
        return [
            "app.name": "SparkleSFTP",
            "nav.connections": isID ? "Koneksi" : "Connections",
            "nav.newConnection": isID ? "Koneksi Baru" : "New Connection",
            "nav.connect": isID ? "Hubungkan" : "Connect",
            "nav.disconnect": isID ? "Putuskan" : "Disconnect",
            "common.refresh": isID ? "Segarkan" : "Refresh",
            "nav.upload": isID ? "Unggah (F5)" : "Upload (F5)",
            "nav.download": isID ? "Unduh (F5)" : "Download (F5)",
            "nav.move": isID ? "Pindah (F6)" : "Move (F6)",
            "nav.newFolder": isID ? "Folder Baru (F7)" : "New Folder (F7)",
            "common.delete": isID ? "Hapus" : "Delete",
            "nav.deleteShortcut": isID ? "Hapus (F8)" : "Delete (F8)",
            "nav.terminal": isID ? "Shell SSH" : "SSH Shell",
            "nav.transfers": isID ? "Antrean Transfer" : "Transfer Queue",
            "nav.synchronize": isID ? "Sinkronisasi" : "Synchronize",
            "conn.plaintextFTPWarning": isID
                ? "PERINGATAN: FTP tanpa enkripsi mengirimkan kredensial dan berkas dalam teks biasa."
                : "WARNING: Plain FTP transmits credentials and files unencrypted.",
            "conn.hostKeyUnknown": isID ? "Verifikasi Sidik Jari Host SSH" : "Verify SSH Host Key Fingerprint",
            "conn.hostKeyMismatch": isID
                ? "BAHAYA: Sidik Jari Host SSH Berubah!"
                : "SECURITY ALERT: SSH Host Key Changed!",
            "nav.securityDiagnostics": isID ? "Diagnostik Keamanan" : "Security Diagnostics",
            "sync.dryRunPreview": isID ? "Pratinjau Dry-Run" : "Dry-Run Preview",
            "sync.executeSync": isID ? "Jalankan Sinkronisasi" : "Execute Sync",
            "nav.settings": isID ? "Pengaturan" : "Settings",
            "tabs.newTab": isID ? "Tab Baru" : "New Tab"
        ]
    }
}
