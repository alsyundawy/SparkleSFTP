import AppKit
import Foundation
import SparkleCore
import SparkleDesignSystem
import SparkleNetworking

public extension AppState {
    private enum PreferenceKey {
        static let language = "sparklesftp.language"
        static let activeLocaleCode = "sparklesftp.activeLocaleCode"
        static let appearanceMode = "sparklesftp.appearanceMode"
        static let themeID = "sparklesftp.selectedThemeID"
        static let maxGlobal = "sparklesftp.maxGlobalTransfers"
        static let maxPerHost = "sparklesftp.maxPerHostTransfers"
        static let pipelineDepth = "sparklesftp.transferPipelineDepth"
        static let useZlib = "sparklesftp.useZlibCompression"
        static let externalTerminal = "sparklesftp.externalTerminalApp"
        static let conflictPolicy = "sparklesftp.conflictPolicy"
        static let uploadConflictPolicy = "sparklesftp.uploadConflictPolicy"
        static let downloadConflictPolicy = "sparklesftp.downloadConflictPolicy"
        static let openInternalEditor = "sparklesftp.openDoubleClickInInternalEditor"
        static let updateSettings = "sparklesftp.autoUpdateSettings"
    }

    internal func loadPersistedPreferences() {
        let defaults = UserDefaults.standard
        loadLocalizationAndThemePreferences(defaults)
        loadTransferAndToolchainPreferences(defaults)
        didLoadPreferences = true
    }

    private func loadLocalizationAndThemePreferences(_ defaults: UserDefaults) {
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
        if let updateData = defaults.data(forKey: PreferenceKey.updateSettings),
           let decoded = try? JSONDecoder().decode(AutoUpdateSettings.self, from: updateData) {
            autoUpdateSettings = decoded
        }
    }

    private func loadTransferAndToolchainPreferences(_ defaults: UserDefaults) {
        let storedGlobal = defaults.integer(forKey: PreferenceKey.maxGlobal)
        if storedGlobal >= 1, storedGlobal <= 16 {
            maxGlobalConcurrentTransfers = storedGlobal
        }
        let storedHost = defaults.integer(forKey: PreferenceKey.maxPerHost)
        if storedHost >= 1, storedHost <= 8 {
            maxPerHostConcurrentTransfers = storedHost
        }
        let storedDepth = defaults.integer(forKey: PreferenceKey.pipelineDepth)
        if storedDepth >= 1, storedDepth <= 16 {
            transferPipelineDepth = storedDepth
        }
        if defaults.object(forKey: PreferenceKey.useZlib) != nil {
            useZlibCompression = defaults.bool(forKey: PreferenceKey.useZlib)
        }
        if let rawTerm = defaults.string(forKey: PreferenceKey.externalTerminal),
           let loadedTerm = ExternalTerminalApp(rawValue: rawTerm) {
            externalTerminalApp = loadedTerm
        }
        if let rawPolicy = defaults.string(forKey: PreferenceKey.conflictPolicy),
           let policy = TransferConflictPolicy(rawValue: rawPolicy) {
            defaultUploadConflictPolicy = policy
            defaultDownloadConflictPolicy = policy
        }
        if let rawUpload = defaults.string(forKey: PreferenceKey.uploadConflictPolicy),
           let uploadPolicy = TransferConflictPolicy(rawValue: rawUpload) {
            defaultUploadConflictPolicy = uploadPolicy
        }
        if let rawDownload = defaults.string(forKey: PreferenceKey.downloadConflictPolicy),
           let downloadPolicy = TransferConflictPolicy(rawValue: rawDownload) {
            defaultDownloadConflictPolicy = downloadPolicy
        }
        if defaults.object(forKey: PreferenceKey.openInternalEditor) != nil {
            openDoubleClickInInternalEditor = defaults.bool(forKey: PreferenceKey.openInternalEditor)
        }
    }

    internal func savePreferencesIfLoaded() {
        guard didLoadPreferences, !isSyncingPreferencesNotification else { return }
        let defaults = UserDefaults.standard
        defaults.set(language.rawValue, forKey: PreferenceKey.language)
        defaults.set(activeLocaleCode, forKey: PreferenceKey.activeLocaleCode)
        defaults.set(appearanceMode.rawValue, forKey: PreferenceKey.appearanceMode)
        defaults.set(selectedThemeID, forKey: PreferenceKey.themeID)
        defaults.set(maxGlobalConcurrentTransfers, forKey: PreferenceKey.maxGlobal)
        defaults.set(maxPerHostConcurrentTransfers, forKey: PreferenceKey.maxPerHost)
        defaults.set(transferPipelineDepth, forKey: PreferenceKey.pipelineDepth)
        defaults.set(useZlibCompression, forKey: PreferenceKey.useZlib)
        defaults.set(externalTerminalApp.rawValue, forKey: PreferenceKey.externalTerminal)
        defaults.set(defaultUploadConflictPolicy.rawValue, forKey: PreferenceKey.conflictPolicy)
        defaults.set(defaultUploadConflictPolicy.rawValue, forKey: PreferenceKey.uploadConflictPolicy)
        defaults.set(defaultDownloadConflictPolicy.rawValue, forKey: PreferenceKey.downloadConflictPolicy)
        defaults.set(openDoubleClickInInternalEditor, forKey: PreferenceKey.openInternalEditor)
        if let encoded = try? JSONEncoder().encode(autoUpdateSettings) {
            defaults.set(encoded, forKey: PreferenceKey.updateSettings)
        }
        NotificationCenter.default.post(name: .sparklePreferencesDidChange, object: windowInstanceID)
    }

    func reloadPreferencesFromNotification() {
        isSyncingPreferencesNotification = true
        let wasLoaded = didLoadPreferences
        didLoadPreferences = false
        loadPersistedPreferences()
        didLoadPreferences = wasLoaded
        refreshLocalizedStrings()
        refreshActivePalette(emitChange: true)
        applyAppearanceToApplication()
        isSyncingPreferencesNotification = false
    }

    func applyAppearanceToApplication() {
        let updated = activePalette
        guard let app = NSApp else { return }
        let targetAppearance = NSAppearance(named: updated.isDark ? .darkAqua : .aqua)
        app.appearance = appearanceMode == .auto ? nil : targetAppearance
        let windowBg = NSColor(hex: updated.windowHex)
        for window in app.windows {
            window.appearance = targetAppearance
            window.backgroundColor = windowBg
        }
    }

    func selectTheme(_ palette: SparkleThemePalette) {
        selectedThemeID = palette.id
        appearanceMode = palette.isDark ? .dark : .light
    }

    func reloadThemes() {
        availableThemes = SparkleThemeStore.loadAllPalettes()
    }

    func refreshLocalizedStrings() {
        strings = AppStrings(
            language: language,
            localeCode: activeLocaleCode,
            availableLocales: availableLocales
        )
        for idx in workspaceTabs.indices where workspaceTabs[idx].sessionID == nil {
            workspaceTabs[idx].title = strings.t("tabs.newTab")
        }
        refreshManagedWindowTitles()
    }

    private func refreshManagedWindowTitles() {
        guard let windows = NSApp?.windows else { return }
        for window in windows {
            switch window.identifier?.rawValue {
            case "sparkle.preferences":
                window.title = strings.t("nav.settings")
            case "sparkle.about":
                window.title = strings.t("nav.about")
            case "sparkle.editor":
                window.title = strings.t("editor.windowTitle")
            default:
                break
            }
        }
    }

    func refreshActivePalette(emitChange: Bool = false) {
        let isDarkSystem = Self.resolveSystemDarkMode()
        let updated = SparkleThemeCatalog.palette(
            id: selectedThemeID,
            appearanceMode: appearanceMode,
            systemIsDark: isDarkSystem,
            available: availableThemes
        )
        if activePalette != updated {
            if emitChange {
                objectWillChange.send()
            }
            activePalette = updated
        }
        applyAppearanceToApplication()
    }

    private static func resolveSystemDarkMode() -> Bool {
        if let app = NSApp, app.appearance == nil {
            return app.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
        let style = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") ?? ""
        return style.caseInsensitiveCompare("Dark") == .orderedSame
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
        if manual {
            presentUpdateCheckAlert(result)
        }
    }

    func presentUpdateCheckAlert(_ status: AutoUpdateCheckStatus) {
        let alert = NSAlert()
        switch status {
        case let .upToDate(version):
            alert.messageText = strings.t("updates.upToDateTitle")
            alert.informativeText = String(format: strings.t("updates.upToDateMessage"), version)
            alert.alertStyle = .informational
            alert.addButton(withTitle: strings.t("common.ok"))
        case let .updateAvailable(version, _, notes):
            alert.messageText = strings.t("updates.updateAvailableTitle")
            let summary = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            let snippet = summary.isEmpty ? "" : "\n\n" + String(summary.prefix(280))
            alert.informativeText = String(format: strings.t("updates.updateAvailableMessage"), version) + snippet
            alert.alertStyle = .informational
            alert.addButton(withTitle: strings.t("updates.viewRelease"))
            alert.addButton(withTitle: strings.t("common.cancel"))
        case let .failed(reason):
            alert.messageText = strings.t("updates.checkFailedTitle")
            alert.informativeText = reason
            alert.alertStyle = .warning
            alert.addButton(withTitle: strings.t("common.ok"))
        case .sparkleNativeTriggered, .checking, .idle:
            return
        }
        if let window = hostWindow ?? NSApp?.keyWindow {
            alert.beginSheetModal(for: window) { response in
                if case let .updateAvailable(_, url, _) = status, response == .alertFirstButtonReturn {
                    NSWorkspace.shared.open(url)
                }
            }
        } else {
            if NSApp == nil || (NSApp?.mainWindow == nil && (ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || ProcessInfo.processInfo.arguments.contains(where: { $0.contains("swiftpm-testing-helper") || $0.contains("xctest") }))) {
                return
            }
            let response = alert.runModal()
            if case let .updateAvailable(_, url, _) = status, response == .alertFirstButtonReturn {
                NSWorkspace.shared.open(url)
            }
        }
    }

    func applyAutoUpdateConfiguration() {
        applyAutoUpdateSettingsAction(autoUpdateSettings)
    }

    func resetAutoUpdateFeedURL() {
        autoUpdateSettings.customFeedURL = AutoUpdateSettings.defaultStableFeedURL
        applyAutoUpdateConfiguration()
    }

    func refreshToolchainReport() async {
        let isSandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
        toolchainReport = await ToolchainInspector.inspectHostToolchain(runSubprocesses: !isSandboxed)
    }
}
