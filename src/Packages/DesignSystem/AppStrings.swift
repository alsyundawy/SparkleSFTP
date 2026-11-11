import Foundation

/// Supported interface languages (English and Bahasa Indonesia).
public enum AppLanguage: String, Sendable, Codable, CaseIterable, Identifiable {
    case english = "en"
    case indonesian = "id"

    public var id: String {
        rawValue
    }

    public var displayName: String {
        switch self {
        case .english: return "English"
        case .indonesian: return "Bahasa Indonesia"
        }
    }
}

/// Type-safe localized UI strings backed by JSON locale catalogs (`Resources/Locales/*.json`)
/// and runtime custom overrides for easy multi-language maintenance.
public struct AppStrings: Sendable {
    public let language: AppLanguage
    public let localeCode: String
    private let englishFallback: [String: String]
    private let table: [String: String]

    public init(
        language: AppLanguage = .english,
        localeCode: String? = nil,
        availableLocales: [LocaleDocument]? = nil
    ) {
        self.language = language
        let resolvedCode = localeCode ?? language.rawValue
        self.localeCode = resolvedCode
        let docs = availableLocales ?? LocalizationCatalog.loadAvailableLocales()
        let englishDoc = docs.first { $0.code == "en" }?.strings ?? LocalizationCatalog.loadBundledStrings(code: "en")
        englishFallback = englishDoc
        table = docs.first { $0.code == resolvedCode }?.strings
            ?? LocalizationCatalog.loadBundledStrings(code: resolvedCode)
    }

    public func t(_ key: String, fallback: String? = nil) -> String {
        if let value = table[key], !value.isEmpty {
            return value
        }
        if let enValue = englishFallback[key], !enValue.isEmpty {
            return enValue
        }
        return fallback ?? key
    }

    public var appName: String {
        t("app.name")
    }

    public var connectionsTitle: String {
        t("nav.connections")
    }

    public var newConnection: String {
        t("nav.newConnection")
    }

    public var connect: String {
        t("nav.connect")
    }

    public var disconnect: String {
        t("nav.disconnect")
    }

    public var refresh: String {
        t("common.refresh")
    }

    public var upload: String {
        t("nav.upload")
    }

    public var download: String {
        t("nav.download")
    }

    public var move: String {
        t("nav.move")
    }

    public var newFolder: String {
        t("nav.newFolder")
    }

    public var delete: String {
        t("nav.deleteShortcut")
    }

    public var terminal: String {
        t("nav.terminal")
    }

    public var transfers: String {
        t("nav.transfers")
    }

    public var synchronize: String {
        t("nav.synchronize")
    }

    public var plaintextFTPWarning: String {
        t("conn.plaintextFTPWarning")
    }

    public var hostKeyUnknownTitle: String {
        t("conn.hostKeyUnknown")
    }

    public var hostKeyMismatchTitle: String {
        t("conn.hostKeyMismatch")
    }

    public var securityDiagnostics: String {
        t("nav.securityDiagnostics")
    }

    public var dryRunPreview: String {
        t("sync.dryRunPreview")
    }

    public var executeSync: String {
        t("sync.executeSync")
    }

    public var settings: String {
        t("nav.settings")
    }
}
