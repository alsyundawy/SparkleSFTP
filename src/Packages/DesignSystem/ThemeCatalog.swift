import Foundation

/// Curated SparkNotePad-inspired developer theme palettes (`ThemePaletteData.h`).
public enum SparkleThemeCatalog {
    public static let defaultLight = SparkleThemePalette(
        id: "notepadNext",
        displayName: "NotepadNext Default",
        family: "NotepadNext",
        isDark: false,
        windowHex: "#F0F2F5",
        canvasHex: "#FAFBFC",
        borderHex: "#E1E4E8",
        primaryTextHex: "#24292F",
        secondaryTextHex: "#57606A",
        accentHex: "#CF222E",
        keywordHex: "#0969DA",
        functionHex: "#0550AE",
        stringHex: "#1A7F37",
        numberHex: "#0550AE",
        operatorHex: "#24292F"
    )

    public static let defaultDark = SparkleThemePalette(
        id: "dracula",
        displayName: "Dracula",
        family: "Dracula",
        isDark: true,
        windowHex: "#1E1F29",
        canvasHex: "#282A36",
        borderHex: "#44475A",
        primaryTextHex: "#F8F8F2",
        secondaryTextHex: "#8897C6",
        accentHex: "#8BE9FD",
        keywordHex: "#8BE9FD",
        functionHex: "#BD93F9",
        stringHex: "#50FA7B",
        numberHex: "#BD93F9",
        operatorHex: "#6272A4"
    )

    public static var builtInPalettes: [SparkleThemePalette] {
        [defaultLight, defaultDark] + coreFamilyPalettes + extendedFamilyPalettes
    }

    static let coreFamilyPalettes: [SparkleThemePalette] = [
        SparkleThemePalette(
            id: "catppuccinMocha",
            displayName: "Catppuccin Mocha",
            family: "Catppuccin",
            isDark: true,
            windowHex: "#11111B",
            canvasHex: "#1E1E2E",
            borderHex: "#313244",
            primaryTextHex: "#CDD6F4",
            secondaryTextHex: "#A6ADC8",
            accentHex: "#74C7EC",
            keywordHex: "#74C7EC",
            functionHex: "#89B4FA",
            stringHex: "#A6E3A1",
            numberHex: "#CBA6F7",
            operatorHex: "#6C7086"
        ),
        SparkleThemePalette(
            id: "catppuccinMacchiato",
            displayName: "Catppuccin Macchiato",
            family: "Catppuccin",
            isDark: true,
            windowHex: "#181926",
            canvasHex: "#24273A",
            borderHex: "#363A4F",
            primaryTextHex: "#CAD3F5",
            secondaryTextHex: "#A5ADCB",
            accentHex: "#7DC4E4",
            keywordHex: "#7DC4E4",
            functionHex: "#8AADF4",
            stringHex: "#A6DA95",
            numberHex: "#C6A0F6",
            operatorHex: "#6E738D"
        ),
        SparkleThemePalette(
            id: "catppuccinLatte",
            displayName: "Catppuccin Latte",
            family: "Catppuccin",
            isDark: false,
            windowHex: "#DCE0E8",
            canvasHex: "#EFF1F5",
            borderHex: "#CCD0DA",
            primaryTextHex: "#4C4F69",
            secondaryTextHex: "#6C6F85",
            accentHex: "#209FB5",
            keywordHex: "#1E66F5",
            functionHex: "#1E66F5",
            stringHex: "#40A02B",
            numberHex: "#8839EF",
            operatorHex: "#9CA0B0"
        ),
        SparkleThemePalette(
            id: "draculaLight",
            displayName: "Dracula Light",
            family: "Dracula",
            isDark: false,
            windowHex: "#F8F8F2",
            canvasHex: "#FFFFFF",
            borderHex: "#E2E8F0",
            primaryTextHex: "#282A36",
            secondaryTextHex: "#6272A4",
            accentHex: "#0097A7",
            keywordHex: "#0097A7",
            functionHex: "#7C4DFF",
            stringHex: "#2E7D32",
            numberHex: "#7C4DFF",
            operatorHex: "#6272A4"
        ),
        SparkleThemePalette(
            id: "tokyoNight",
            displayName: "Tokyo Night",
            family: "Tokyo Night",
            isDark: true,
            windowHex: "#16161E",
            canvasHex: "#1A1B26",
            borderHex: "#2F334D",
            primaryTextHex: "#C0CAF5",
            secondaryTextHex: "#9AA5CE",
            accentHex: "#2AC3DE",
            keywordHex: "#7DCFFF",
            functionHex: "#7AA2F7",
            stringHex: "#9ECE6A",
            numberHex: "#BB9AF7",
            operatorHex: "#565F89"
        ),
        SparkleThemePalette(
            id: "tokyoNightLight",
            displayName: "Tokyo Night Light",
            family: "Tokyo Night",
            isDark: false,
            windowHex: "#D5D6DB",
            canvasHex: "#E1E2E7",
            borderHex: "#CFC9C2",
            primaryTextHex: "#343B58",
            secondaryTextHex: "#565A6E",
            accentHex: "#007197",
            keywordHex: "#0F4B6E",
            functionHex: "#2E7DE9",
            stringHex: "#587539",
            numberHex: "#9854F1",
            operatorHex: "#8990B3"
        ),
        SparkleThemePalette(
            id: "nordDark",
            displayName: "Nord Dark",
            family: "Nord",
            isDark: true,
            windowHex: "#242933",
            canvasHex: "#2E3440",
            borderHex: "#3B4252",
            primaryTextHex: "#D8DEE9",
            secondaryTextHex: "#88C0D0",
            accentHex: "#8FBCBB",
            keywordHex: "#88C0D0",
            functionHex: "#81A1C1",
            stringHex: "#A3BE8C",
            numberHex: "#B48EAD",
            operatorHex: "#4C566A"
        ),
        SparkleThemePalette(
            id: "nordLight",
            displayName: "Nord Light",
            family: "Nord",
            isDark: false,
            windowHex: "#E5E9F0",
            canvasHex: "#ECEFF4",
            borderHex: "#D8DEE9",
            primaryTextHex: "#2E3440",
            secondaryTextHex: "#4C566A",
            accentHex: "#3B626E",
            keywordHex: "#5E81AC",
            functionHex: "#81A1C1",
            stringHex: "#4C704C",
            numberHex: "#83587A",
            operatorHex: "#9DA6B8"
        ),
        SparkleThemePalette(
            id: "oneDarkPro",
            displayName: "One Dark Pro",
            family: "One Dark",
            isDark: true,
            windowHex: "#21252B",
            canvasHex: "#282C34",
            borderHex: "#3E4451",
            primaryTextHex: "#DCDFE4",
            secondaryTextHex: "#828997",
            accentHex: "#56B6C2",
            keywordHex: "#56B6C2",
            functionHex: "#61AFEF",
            stringHex: "#98C379",
            numberHex: "#C678DD",
            operatorHex: "#4B5263"
        ),
        SparkleThemePalette(
            id: "oneLight",
            displayName: "One Light",
            family: "One Dark",
            isDark: false,
            windowHex: "#EAEAEC",
            canvasHex: "#FAFAFA",
            borderHex: "#DBDBDC",
            primaryTextHex: "#383A42",
            secondaryTextHex: "#696C77",
            accentHex: "#0184BC",
            keywordHex: "#0184BC",
            functionHex: "#4078F2",
            stringHex: "#50A14F",
            numberHex: "#A626A4",
            operatorHex: "#A0A1A7"
        )
    ]

    public static func palette(
        id: String,
        appearanceMode: ThemeAppearanceMode = .auto,
        systemIsDark: Bool = false,
        available: [SparkleThemePalette] = builtInPalettes
    ) -> SparkleThemePalette {
        let wantDark: Bool = switch appearanceMode {
        case .light: false
        case .dark: true
        case .auto: systemIsDark
        }

        if let direct = available.first(where: { $0.id.caseInsensitiveCompare(id) == .orderedSame }) {
            if appearanceMode == .auto || direct.isDark == wantDark {
                return direct
            }
            if let familyVariant = available.first(where: { $0.family == direct.family && $0.isDark == wantDark }) {
                return familyVariant
            }
            return direct
        }
        return wantDark ? defaultDark : defaultLight
    }
}
