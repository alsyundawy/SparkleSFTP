import AppKit
import SwiftUI

/// Controls global Light/Dark/System appearance resolution alongside custom theme palettes.
public enum ThemeAppearanceMode: String, Sendable, Codable, CaseIterable, Identifiable {
    case auto
    case light
    case dark

    public var id: String {
        rawValue
    }
}

public struct ThemeRGBComponents: Sendable, Equatable {
    public let red: Double
    public let green: Double
    public let blue: Double
}

/// Color palette definition inspired by SparkNotePad (`ThemePaletteData.h`),
/// providing semantic chrome and syntax colors with WCAG 2.1 contrast helpers.
public struct SparkleThemePalette: Identifiable, Sendable, Codable, Equatable {
    public let id: String
    public let displayName: String
    public let family: String
    public let isDark: Bool
    public let windowHex: String
    public let canvasHex: String
    public let borderHex: String
    public let primaryTextHex: String
    public let secondaryTextHex: String
    public let accentHex: String
    public let keywordHex: String
    public let functionHex: String
    public let stringHex: String
    public let numberHex: String
    public let operatorHex: String

    public init(
        id: String,
        displayName: String,
        family: String,
        isDark: Bool,
        windowHex: String,
        canvasHex: String,
        borderHex: String,
        primaryTextHex: String,
        secondaryTextHex: String,
        accentHex: String,
        keywordHex: String,
        functionHex: String,
        stringHex: String,
        numberHex: String,
        operatorHex: String
    ) {
        self.id = id
        self.displayName = displayName
        self.family = family
        self.isDark = isDark
        self.windowHex = windowHex
        self.canvasHex = canvasHex
        self.borderHex = borderHex
        self.primaryTextHex = primaryTextHex
        self.secondaryTextHex = secondaryTextHex
        self.accentHex = accentHex
        self.keywordHex = keywordHex
        self.functionHex = functionHex
        self.stringHex = stringHex
        self.numberHex = numberHex
        self.operatorHex = operatorHex
    }

    public var windowColor: Color {
        Color(hex: windowHex)
    }

    public var canvasColor: Color {
        Color(hex: canvasHex)
    }

    public var borderColor: Color {
        Color(hex: borderHex)
    }

    public var primaryTextColor: Color {
        Color(hex: primaryTextHex)
    }

    public var secondaryTextColor: Color {
        Color(hex: secondaryTextHex)
    }

    public var accentColor: Color {
        Color(hex: accentHex)
    }

    public var surfaceColor: Color {
        isDark ? windowColor : canvasColor
    }

    public var selectionColor: Color {
        accentColor.opacity(isDark ? 0.28 : 0.16)
    }

    public var keywordColor: Color {
        Color(hex: keywordHex)
    }

    public var functionColor: Color {
        Color(hex: functionHex)
    }

    public var stringColor: Color {
        Color(hex: stringHex)
    }

    public var numberColor: Color {
        Color(hex: numberHex)
    }

    public var operatorColor: Color {
        Color(hex: operatorHex)
    }

    public var primaryContrastRatio: Double {
        Self.contrastRatio(hexA: primaryTextHex, hexB: canvasHex)
    }

    public var meetsWCAGAA: Bool {
        primaryContrastRatio >= 4.5
    }

    public static func rgbComponents(fromHex hex: String) -> ThemeRGBComponents? {
        var sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if sanitized.hasPrefix("#") {
            sanitized.removeFirst()
        }
        guard sanitized.count == 6, let value = UInt64(sanitized, radix: 16) else {
            return nil
        }
        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        return ThemeRGBComponents(red: red, green: green, blue: blue)
    }

    public static func relativeLuminance(ofHex hex: String) -> Double {
        guard let rgb = rgbComponents(fromHex: hex) else { return 0.5 }
        func linear(_ channel: Double) -> Double {
            channel <= 0.03928 ? (channel / 12.92) : pow((channel + 0.055) / 1.055, 2.4)
        }
        return (0.2126 * linear(rgb.red)) + (0.7152 * linear(rgb.green)) + (0.0722 * linear(rgb.blue))
    }

    public static func contrastRatio(hexA: String, hexB: String) -> Double {
        let lum1 = relativeLuminance(ofHex: hexA)
        let lum2 = relativeLuminance(ofHex: hexB)
        let lighter = max(lum1, lum2)
        let darker = min(lum1, lum2)
        return (lighter + 0.05) / (darker + 0.05)
    }
}

/// Manages custom user JSON themes alongside built-in SparkNotePad palettes.
public enum SparkleThemeStore {
    public static var customThemesDirectoryURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return appSupport
            .appendingPathComponent("SparkleSFTP", isDirectory: true)
            .appendingPathComponent("Themes", isDirectory: true)
    }

    public static func loadAllPalettes(customDirectory: URL = customThemesDirectoryURL) -> [SparkleThemePalette] {
        var result = SparkleThemeCatalog.builtInPalettes
        var seenIDs = Set(result.map(\.id))

        for custom in loadCustomPalettes(from: customDirectory) where isValidPalette(custom) {
            if let existingIndex = result.firstIndex(where: { $0.id == custom.id }) {
                result[existingIndex] = custom
            } else if !seenIDs.contains(custom.id) {
                seenIDs.insert(custom.id)
                result.append(custom)
            }
        }
        return result
    }

    public static func loadCustomPalettes(from directory: URL = customThemesDirectoryURL) -> [SparkleThemePalette] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let decoder = JSONDecoder()
        var loaded: [SparkleThemePalette] = []
        for fileURL in files where fileURL.pathExtension.lowercased() == "json" {
            guard let data = try? Data(contentsOf: fileURL) else { continue }
            if let single = try? decoder.decode(SparkleThemePalette.self, from: data), isValidPalette(single) {
                loaded.append(single)
            } else if let array = try? decoder.decode([SparkleThemePalette].self, from: data) {
                loaded.append(contentsOf: array.filter(isValidPalette))
            }
        }
        return loaded
    }

    public static func importThemeFile(
        from sourceURL: URL,
        into directory: URL = customThemesDirectoryURL
    ) throws -> [SparkleThemePalette] {
        let didScope = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didScope {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }
        let data = try Data(contentsOf: sourceURL)
        let decoder = JSONDecoder()
        let parsed: [SparkleThemePalette] = if let single = try? decoder.decode(SparkleThemePalette.self, from: data) {
            [single]
        } else {
            try decoder.decode([SparkleThemePalette].self, from: data)
        }
        let valid = parsed.filter(isValidPalette)
        guard !valid.isEmpty else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let safeName = sourceURL.lastPathComponent.hasSuffix(".json")
            ? sourceURL.lastPathComponent
            : "\(sourceURL.deletingPathExtension().lastPathComponent).json"
        let dest = directory.appendingPathComponent(safeName, isDirectory: false)
        try data.write(to: dest, options: [.atomic])
        return valid
    }

    public static func exportSampleTheme(to url: URL, palette: SparkleThemePalette) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(palette)
        try data.write(to: url, options: [.atomic])
    }

    public static func isValidPalette(_ palette: SparkleThemePalette) -> Bool {
        !palette.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !palette.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && SparkleThemePalette.rgbComponents(fromHex: palette.windowHex) != nil
            && SparkleThemePalette.rgbComponents(fromHex: palette.canvasHex) != nil
            && SparkleThemePalette.rgbComponents(fromHex: palette.primaryTextHex) != nil
            && SparkleThemePalette.rgbComponents(fromHex: palette.accentHex) != nil
    }
}
