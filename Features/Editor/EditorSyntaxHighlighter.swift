import AppKit
import Foundation
import SparkleDesignSystem

/// Lightweight regex-based syntax highlighter styled directly from the active `SparkleThemePalette`.
public enum EditorSyntaxHighlighter {
    private static let maxHighlightCharacters = 256_000

    public static func applyHighlighting(
        to textStorage: NSTextStorage,
        language: EditorSyntaxLanguage,
        palette: SparkleThemePalette,
        font: NSFont
    ) {
        let fullLength = textStorage.length
        let fullRange = NSRange(location: 0, length: fullLength)
        textStorage.beginEditing()
        defer { textStorage.endEditing() }

        let baseColor = NSColor(hex: palette.primaryTextHex)
        textStorage.setAttributes([
            .font: font,
            .foregroundColor: baseColor
        ], range: fullRange)

        guard language != .plainText, fullLength > 0, fullLength <= maxHighlightCharacters else {
            return
        }

        let source = textStorage.string
        let patterns = ruleSet(for: language, palette: palette)
        for rule in patterns {
            guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: rule.options) else {
                continue
            }
            let color = NSColor(hex: rule.hexColor)
            regex.enumerateMatches(in: source, options: [], range: fullRange) { match, _, _ in
                guard let range = match?.range, range.location != NSNotFound else { return }
                textStorage.addAttribute(.foregroundColor, value: color, range: range)
            }
        }
    }

    private struct HighlightRule {
        let pattern: String
        let hexColor: String
        let options: NSRegularExpression.Options
    }

    private static func ruleSet(
        for language: EditorSyntaxLanguage,
        palette: SparkleThemePalette
    ) -> [HighlightRule] {
        switch language {
        case .auto, .plainText:
            return []
        case .swift, .shell:
            return codeRules(language: language, palette: palette)
        case .json:
            return jsonRules(palette: palette)
        case .yaml, .iniConfig:
            return configRules(palette: palette)
        case .xmlHTML:
            return xmlRules(palette: palette)
        case .markdown:
            return markdownRules(palette: palette)
        case .sql:
            return sqlRules(palette: palette)
        case .log:
            return logRules(palette: palette)
        }
    }

    private static func jsonRules(palette: SparkleThemePalette) -> [HighlightRule] {
        [
            HighlightRule(pattern: "\"([^\"\\\\]|\\\\.)*\"", hexColor: palette.stringHex, options: []),
            HighlightRule(pattern: "\"([^\"\\\\]|\\\\.)*\"(?=\\s*:)", hexColor: palette.keywordHex, options: []),
            HighlightRule(pattern: "\\b(true|false|null)\\b", hexColor: palette.functionHex, options: []),
            HighlightRule(pattern: "-?\\b\\d+(\\.\\d+)?\\b", hexColor: palette.numberHex, options: [])
        ]
    }

    private static func configRules(palette: SparkleThemePalette) -> [HighlightRule] {
        [
            HighlightRule(
                pattern: "^[A-Za-z0-9_.-]+(?=\\s*[:=])",
                hexColor: palette.keywordHex,
                options: [.anchorsMatchLines]
            ),
            HighlightRule(pattern: "^\\[[^\\]]+\\]", hexColor: palette.functionHex, options: [.anchorsMatchLines]),
            HighlightRule(pattern: "\"([^\"\\\\]|\\\\.)*\"|'[^']*'", hexColor: palette.stringHex, options: []),
            HighlightRule(
                pattern: "\\b(true|false|yes|no|null|\\d+(\\.\\d+)?)\\b",
                hexColor: palette.numberHex,
                options: [.caseInsensitive]
            ),
            HighlightRule(
                pattern: "(^|\\s)[#;].*$",
                hexColor: palette.secondaryTextHex,
                options: [.anchorsMatchLines]
            )
        ]
    }

    private static func xmlRules(palette: SparkleThemePalette) -> [HighlightRule] {
        [
            HighlightRule(pattern: "</?[A-Za-z0-9:_-]+", hexColor: palette.keywordHex, options: []),
            HighlightRule(pattern: "/?>", hexColor: palette.operatorHex, options: []),
            HighlightRule(pattern: "\\b[A-Za-z0-9:_-]+(?=\\=)", hexColor: palette.functionHex, options: []),
            HighlightRule(pattern: "\"[^\"]*\"|'[^']*'", hexColor: palette.stringHex, options: []),
            HighlightRule(pattern: "<!--[\\s\\S]*?-->", hexColor: palette.secondaryTextHex, options: [])
        ]
    }

    private static func markdownRules(palette: SparkleThemePalette) -> [HighlightRule] {
        [
            HighlightRule(pattern: "^#{1,6}\\s+.*$", hexColor: palette.keywordHex, options: [.anchorsMatchLines]),
            HighlightRule(pattern: "`[^`]+`", hexColor: palette.stringHex, options: []),
            HighlightRule(pattern: "\\*\\*[^*]+\\*\\*", hexColor: palette.functionHex, options: []),
            HighlightRule(pattern: "\\[[^\\]]+\\]\\([^\\)]+\\)", hexColor: palette.accentHex, options: [])
        ]
    }

    private static func sqlRules(palette: SparkleThemePalette) -> [HighlightRule] {
        let keywords = "\\b(SELECT|FROM|WHERE|INSERT|INTO|UPDATE|DELETE|"
            + "CREATE|TABLE|ALTER|DROP|JOIN|ON|GROUP|ORDER|BY|LIMIT|PRAGMA|BEGIN|COMMIT)\\b"
        return [
            HighlightRule(pattern: keywords, hexColor: palette.keywordHex, options: [.caseInsensitive]),
            HighlightRule(pattern: "'([^'\\\\]|\\\\.)*'", hexColor: palette.stringHex, options: []),
            HighlightRule(pattern: "\\b\\d+(\\.\\d+)?\\b", hexColor: palette.numberHex, options: []),
            HighlightRule(pattern: "--.*$", hexColor: palette.secondaryTextHex, options: [.anchorsMatchLines])
        ]
    }

    private static func logRules(palette: SparkleThemePalette) -> [HighlightRule] {
        [
            HighlightRule(
                pattern: "\\b(ERROR|FATAL|CRITICAL|FAIL|FAILED)\\b",
                hexColor: palette.accentHex,
                options: []
            ),
            HighlightRule(pattern: "\\b(WARN|WARNING)\\b", hexColor: palette.numberHex, options: []),
            HighlightRule(pattern: "\\b(INFO|DEBUG|OK|PASS|SUCCESS)\\b", hexColor: palette.stringHex, options: []),
            HighlightRule(
                pattern: "\\d{4}-\\d{2}-\\d{2}[T ]\\d{2}:\\d{2}:\\d{2}[^\\s]*",
                hexColor: palette.keywordHex,
                options: []
            )
        ]
    }

    private static func codeRules(
        language: EditorSyntaxLanguage,
        palette: SparkleThemePalette
    ) -> [HighlightRule] {
        let swiftKeywords = "\\b(import|struct|class|actor|enum|protocol|func|let|var|"
            + "if|else|guard|return|switch|case|default|for|while|do|try|catch|"
            + "throw|throws|async|await|public|private|internal|static|extension|true|false|nil|self)\\b"
        let shellKeywords = "\\b(if|then|else|elif|fi|for|do|done|while|case|"
            + "esac|function|return|exit|local|export|set|true|false)\\b"
        let kwPattern = language == .swift ? swiftKeywords : shellKeywords
        let commentPattern = language == .swift ? "//.*$|/\\*[\\s\\S]*?\\*/" : "#.*$"
        return [
            HighlightRule(pattern: kwPattern, hexColor: palette.keywordHex, options: []),
            HighlightRule(
                pattern: "@[A-Za-z_][A-Za-z0-9_]*|\\$[A-Za-z_{][A-Za-z0-9_}]*",
                hexColor: palette.functionHex,
                options: []
            ),
            HighlightRule(pattern: "\"([^\"\\\\]|\\\\.)*\"|'[^']*'", hexColor: palette.stringHex, options: []),
            HighlightRule(pattern: "\\b\\d+(\\.\\d+)?\\b", hexColor: palette.numberHex, options: []),
            HighlightRule(pattern: commentPattern, hexColor: palette.secondaryTextHex, options: [.anchorsMatchLines])
        ]
    }
}
