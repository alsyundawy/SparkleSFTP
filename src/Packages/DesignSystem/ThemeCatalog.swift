import Foundation

/// Curated SparkNotePad & NotepadNext theme catalog (76 built-in themes across 26 families with WCAG AA contrast).
public enum SparkleThemeCatalog {
    public static var defaultLight: SparkleThemePalette {
        builtInPalettes[0]
    }

    public static var defaultDark: SparkleThemePalette {
        builtInPalettes.first { $0.id == "dracula" } ?? builtInPalettes[1]
    }

    public static var builtInFamilies: [String] {
        var seen: [String] = []
        for item in builtInPalettes where !seen.contains(item.family) {
            seen.append(item.family)
        }
        return seen
    }

    public static let builtInPalettes: [SparkleThemePalette] =
        corePalettes + extendedPalettes + spectrumPalettes + studioPalettes

    public static func palette(
        id: String,
        appearanceMode: ThemeAppearanceMode,
        systemIsDark: Bool,
        available: [SparkleThemePalette] = builtInPalettes
    ) -> SparkleThemePalette {
        let wantsDark: Bool = switch appearanceMode {
        case .auto:
            systemIsDark
        case .light:
            false
        case .dark:
            true
        }

        if let exact = available.first(where: { $0.id == id }) {
            if exact.isDark == wantsDark {
                return exact
            }
            if let familyVariant = available.first(where: { $0.family == exact.family && $0.isDark == wantsDark }) {
                return familyVariant
            }
        }
        return wantsDark
            ? (available.first(where: \.isDark) ?? defaultDark)
            : (available.first(where: { !$0.isDark }) ?? defaultLight)
    }
}
