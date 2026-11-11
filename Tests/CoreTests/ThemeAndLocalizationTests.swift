import Foundation
import SparkleCore
@testable import SparkleDesignSystem
import Testing

@Suite("SparkleTheme & Localization Catalog Tests")
struct ThemeAndLocalizationTests {
    @Test("SparkleThemeCatalog provides all 76 SparkNotePad palettes across 26 families with WCAG AA contrast")
    func curatedThemesAndWCAGContrast() {
        let palettes = SparkleThemeCatalog.builtInPalettes
        #expect(palettes.count == 76)
        #expect(SparkleThemeCatalog.builtInFamilies.count == 26)
        for palette in palettes {
            #expect(SparkleThemeStore.isValidPalette(palette))
            #expect(palette.meetsWCAGAA, "Theme \(palette.id) primary contrast below 4.5:1")
            let winContrast = SparkleThemePalette.contrastRatio(
                hexA: palette.primaryTextHex,
                hexB: palette.windowHex
            )
            #expect(winContrast >= 4.5, "Theme \(palette.id) window contrast \(winContrast) below 4.5:1")
        }

        let draculaInLight = SparkleThemeCatalog.palette(
            id: "dracula",
            appearanceMode: .light,
            systemIsDark: false
        )
        #expect(!draculaInLight.isDark)
        #expect(draculaInLight.family == "Dracula")
    }

    @Test("SparkleThemeStore imports and exports custom JSON themes cleanly")
    func customThemeImportExportRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SparkleThemeTest-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let custom = SparkleThemePalette(
            id: "sparkOceanTest",
            displayName: "Spark Ocean Test",
            family: "Ocean",
            isDark: true,
            windowHex: "#101820",
            canvasHex: "#16202B",
            borderHex: "#243447",
            primaryTextHex: "#EDF2F7",
            secondaryTextHex: "#8899A6",
            accentHex: "#38BDF8",
            keywordHex: "#38BDF8",
            functionHex: "#60A5FA",
            stringHex: "#34D399",
            numberHex: "#A78BFA",
            operatorHex: "#CBD5E1"
        )
        let sampleURL = dir.appendingPathComponent("custom.json")
        try SparkleThemeStore.exportSampleTheme(to: sampleURL, palette: custom)
        let customStoreDir = dir.appendingPathComponent("Themes", isDirectory: true)
        let imported = try SparkleThemeStore.importThemeFile(from: sampleURL, into: customStoreDir)
        #expect(imported.first?.id == "sparkOceanTest")

        let all = SparkleThemeStore.loadAllPalettes(customDirectory: customStoreDir)
        #expect(all.contains { $0.id == "sparkOceanTest" })
    }

    @Test("Bundled en.json and id.json locales stay synchronized with 100% key coverage")
    func localizationParityAndCustomOverrides() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SparkleLocaleTest-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(LocalizationCatalog.resolveResourceBundle() != nil)
        let englishStrings = LocalizationCatalog.loadBundledStrings(code: "en")
        let indonesianStrings = LocalizationCatalog.loadBundledStrings(code: "id")
        #expect(englishStrings.count >= 260)

        let idDoc = LocaleDocument(code: "id", displayName: "Bahasa Indonesia", strings: indonesianStrings)
        let missing = LocalizationCatalog.missingKeys(for: idDoc, referenceKeys: Set(englishStrings.keys))
        #expect(missing.isEmpty, "Missing keys in id.json: \(missing)")
        #expect(LocalizationCatalog.coveragePercentage(for: idDoc, referenceKeys: Set(englishStrings.keys)) == 100.0)

        let overrideFile = dir.appendingPathComponent("fr.json")
        let frDoc = LocaleDocument(code: "fr", displayName: "Français", strings: ["nav.connect": "Connecter"])
        try LocalizationCatalog.exportLocaleDocument(frDoc, to: overrideFile)

        let customDir = dir.appendingPathComponent("CustomLocales", isDirectory: true)
        _ = try LocalizationCatalog.importLocaleFile(from: overrideFile, into: customDir)
        let loaded = LocalizationCatalog.loadAvailableLocales(customDirectory: customDir)
        let frStrings = AppStrings(language: .english, localeCode: "fr", availableLocales: loaded)
        #expect(frStrings.t("nav.connect") == "Connecter")
        #expect(frStrings.t("nav.disconnect") == "Disconnect")
    }
}
