import Foundation

/// Identifier for Settings tabs in SparkleSFTP v0.6.0.
public enum SettingsTabIdentifier: String, Sendable, Codable, CaseIterable, Identifiable {
    case general
    case themes
    case terminal
    case editor
    case security
    case network
    case sync
    case transfers
    case archives
    case updates

    public var id: String {
        rawValue
    }

    public var titleKey: String {
        switch self {
        case .general: return "prefs.tabGeneral"
        case .themes: return "prefs.tabThemes"
        case .terminal: return "prefs.tabTerminal"
        case .editor: return "prefs.tabEditor"
        case .security: return "prefs.tabSecurity"
        case .network: return "prefs.tabNetwork"
        case .sync: return "prefs.tabSync"
        case .transfers: return "prefs.tabTransfers"
        case .archives: return "prefs.tabArchives"
        case .updates: return "prefs.tabUpdates"
        }
    }

    public var iconName: String {
        switch self {
        case .general: return "gearshape"
        case .themes: return "paintpalette"
        case .terminal: return "terminal"
        case .editor: return "doc.text"
        case .security: return "lock.shield"
        case .network: return "network"
        case .sync: return "arrow.triangle.2.circlepath"
        case .transfers: return "arrow.up.arrow.down.circle"
        case .archives: return "archivebox"
        case .updates: return "arrow.triangle.turn.up.right.circle"
        }
    }
}

/// Primitive type declaration for a setting descriptor.
public enum SettingsValueType: String, Sendable, Codable {
    case string
    case int
    case double
    case bool
    case enumChoice
}

/// A descriptor representing a single configurable setting in SparkleSFTP.
public struct SettingDescriptor: Identifiable, Sendable, Equatable {
    public let id: String
    public let key: String
    public let tab: SettingsTabIdentifier
    public let titleKey: String
    public let descriptionKey: String
    public let valueType: SettingsValueType
    public let defaultValue: String
    public let minValue: Double?
    public let maxValue: Double?

    public init(
        key: String,
        tab: SettingsTabIdentifier,
        titleKey: String,
        descriptionKey: String = "",
        valueType: SettingsValueType,
        defaultValue: String,
        minValue: Double? = nil,
        maxValue: Double? = nil
    ) {
        id = key
        self.key = key
        self.tab = tab
        self.titleKey = titleKey
        self.descriptionKey = descriptionKey
        self.valueType = valueType
        self.defaultValue = defaultValue
        self.minValue = minValue
        self.maxValue = maxValue
    }
}

/// Central registry powering Settings Search, Export/Import, and Defaults Reset (F-02).
public enum SettingsRegistry {
    /// Filters setting descriptors matching query string across keys, titles, or tab names.
    public static func search(query: String) -> [SettingDescriptor] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return allSettings }
        return allSettings.filter { item in
            item.key.lowercased().contains(trimmed) ||
                item.titleKey.lowercased().contains(trimmed) ||
                item.tab.rawValue.lowercased().contains(trimmed)
        }
    }

    /// Returns all settings associated with a specific tab.
    public static func settings(for tab: SettingsTabIdentifier) -> [SettingDescriptor] {
        allSettings.filter { $0.tab == tab }
    }
}
