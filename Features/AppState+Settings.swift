import AppKit
import Foundation
import SparkleCore
import SparkleDesignSystem

public extension AppState {
    private enum PreferenceKey {
        static let language = "sparklesftp.language"
        static let activeLocaleCode = "sparklesftp.activeLocaleCode"
        static let appearanceMode = "sparklesftp.appearanceMode"
        static let themeID = "sparklesftp.selectedThemeID"
        static let maxGlobal = "sparklesftp.maxGlobalTransfers"
        static let maxPerHost = "sparklesftp.maxPerHostTransfers"
        static let conflictPolicy = "sparklesftp.conflictPolicy"
        static let openInternalEditor = "sparklesftp.openDoubleClickInInternalEditor"
        static let updateSettings = "sparklesftp.autoUpdateSettings"
    }

    internal func loadPersistedPreferences() {
        let defaults = UserDefaults.standard
        if let rawLang = defaults.string(forKey: PreferenceKey.language),
           let loadedLang = AppLanguage(rawValue: rawLang) {
            language = loadedLang
        }
        if let rawLocale = defaults.string(forKey: PreferenceKey.activeLocaleCode), !rawLocale.isEmpty {
            activeLocaleCode = rawLocale
        } else {
            activeLocaleCode = language.rawValue
        }
        if let rawMode = defaults.string(forKey: PreferenceKey.appearanceMode),
           let mode = ThemeAppearanceMode(rawValue: rawMode) {
            appearanceMode = mode
        }
        if let savedTheme = defaults.string(forKey: PreferenceKey.themeID), !savedTheme.isEmpty {
            selectedThemeID = savedTheme
        }
        let storedGlobal = defaults.integer(forKey: PreferenceKey.maxGlobal)
        if storedGlobal >= 1, storedGlobal <= 8 {
            maxGlobalConcurrentTransfers = storedGlobal
        }
        let storedHost = defaults.integer(forKey: PreferenceKey.maxPerHost)
        if storedHost >= 1, storedHost <= 4 {
            maxPerHostConcurrentTransfers = storedHost
        }
        if let rawPolicy = defaults.string(forKey: PreferenceKey.conflictPolicy),
           let policy = TransferConflictPolicy(rawValue: rawPolicy) {
            defaultConflictPolicy = policy
        }
        if defaults.object(forKey: PreferenceKey.openInternalEditor) != nil {
            openDoubleClickInInternalEditor = defaults.bool(forKey: PreferenceKey.openInternalEditor)
        }
        if let updateData = defaults.data(forKey: PreferenceKey.updateSettings),
           let decoded = try? JSONDecoder().decode(AutoUpdateSettings.self, from: updateData) {
            autoUpdateSettings = decoded
        }
        didLoadPreferences = true
    }

    internal func savePreferencesIfLoaded() {
        guard didLoadPreferences else { return }
        let defaults = UserDefaults.standard
        defaults.set(language.rawValue, forKey: PreferenceKey.language)
        defaults.set(activeLocaleCode, forKey: PreferenceKey.activeLocaleCode)
        defaults.set(appearanceMode.rawValue, forKey: PreferenceKey.appearanceMode)
        defaults.set(selectedThemeID, forKey: PreferenceKey.themeID)
        defaults.set(maxGlobalConcurrentTransfers, forKey: PreferenceKey.maxGlobal)
        defaults.set(maxPerHostConcurrentTransfers, forKey: PreferenceKey.maxPerHost)
        defaults.set(defaultConflictPolicy.rawValue, forKey: PreferenceKey.conflictPolicy)
        defaults.set(openDoubleClickInInternalEditor, forKey: PreferenceKey.openInternalEditor)
        if let encoded = try? JSONEncoder().encode(autoUpdateSettings) {
            defaults.set(encoded, forKey: PreferenceKey.updateSettings)
        }
    }

    func applyAppearanceToApplication() {
        guard NSApp != nil else { return }
        switch appearanceMode {
        case .auto:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    func selectTheme(_ palette: SparkleThemePalette) {
        selectedThemeID = palette.id
        appearanceMode = palette.isDark ? .dark : .light
    }

    func reloadThemes() {
        availableThemes = SparkleThemeStore.loadAllPalettes()
    }

    func importThemeFile(from url: URL) {
        do {
            let imported = try SparkleThemeStore.importThemeFile(from: url)
            reloadThemes()
            if let first = imported.first {
                selectTheme(first)
                statusBannerMessage = "Imported theme '\(first.displayName)'"
            }
        } catch {
            lastError = .persistenceFailure(reason: error.localizedDescription)
        }
    }

    func exportActiveThemeSample(to url: URL) {
        do {
            try SparkleThemeStore.exportSampleTheme(to: url, palette: activePalette)
            statusBannerMessage = "Exported theme JSON: \(url.lastPathComponent)"
        } catch {
            lastError = .persistenceFailure(reason: error.localizedDescription)
        }
    }

    func reloadLocales() {
        availableLocales = LocalizationCatalog.loadAvailableLocales()
    }

    func selectLocale(code: String) {
        if let builtIn = AppLanguage(rawValue: code) {
            language = builtIn
        }
        activeLocaleCode = code
    }

    func importLocaleFile(from url: URL) {
        do {
            let imported = try LocalizationCatalog.importLocaleFile(from: url)
            reloadLocales()
            selectLocale(code: imported.code)
            statusBannerMessage = "Loaded locale '\(imported.displayName)' (\(imported.strings.count) keys)"
        } catch {
            lastError = .persistenceFailure(reason: error.localizedDescription)
        }
    }

    func exportCurrentLocaleTemplate(to url: URL) {
        do {
            let doc = availableLocales.first { $0.code == activeLocaleCode }
                ?? LocaleDocument(code: activeLocaleCode, displayName: activeLocaleCode.uppercased(), strings: [:])
            try LocalizationCatalog.exportLocaleDocument(doc, to: url)
            statusBannerMessage = "Exported locale JSON: \(url.lastPathComponent)"
        } catch {
            lastError = .persistenceFailure(reason: error.localizedDescription)
        }
    }

    func checkForUpdates(manual: Bool = true) async {
        autoUpdateStatus = .checking
        let result = await performUpdateCheckAction(autoUpdateSettings, manual)
        autoUpdateStatus = result
        var updated = autoUpdateSettings
        updated.lastCheckedAt = Date()
        autoUpdateSettings = updated
    }

    func applyAutoUpdateConfiguration() {
        applyAutoUpdateSettingsAction(autoUpdateSettings)
    }

    func resetAutoUpdateFeedURL() {
        autoUpdateSettings.customFeedURL = AutoUpdateSettings.defaultStableFeedURL
        applyAutoUpdateConfiguration()
    }
}
