import AppKit
import Foundation
import SparkleDesignSystem

/// Lightweight regex-based syntax highlighter styled directly from the active `SparkleThemePalette`.
public enum EditorSyntaxHighlighter {
    private static let maxHighlightCharacters = 64_000

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
        if let rules = codeAndScriptRules(for: language, palette: palette) {
            return rules
        }
        return markupAndConfigRules(for: language, palette: palette)
    }

    private static func codeAndScriptRules(
        for language: EditorSyntaxLanguage,
        palette: SparkleThemePalette
    ) -> [HighlightRule]? {
        switch language {
        case .swift, .cLanguage, .cpp, .objectiveC, .rust, .golang, .java, .kotlin, .csharp, .scala, .dart,
             .javascript, .typescript, .jsx, .tsx, .vue, .svelte, .php:
            return codeRules(language: language, palette: palette)
        case .python, .ruby, .perl, .lua, .rLanguage, .julia, .shell, .zsh, .fish, .powershell, .batch:
            return scriptingRules(language: language, palette: palette)
        default:
            return nil
        }
    }

    private static func markupAndConfigRules(
        for language: EditorSyntaxLanguage,
        palette: SparkleThemePalette
    ) -> [HighlightRule] {
        switch language {
        case .auto, .plainText:
            return []
        case .html, .xmlHTML:
            return xmlRules(palette: palette)
        case .css, .scss, .less:
            return cssRules(palette: palette)
        case .json:
            return jsonRules(palette: palette)
        case .yaml, .toml, .iniConfig, .properties, .dockerfile, .nginx, .apache, .makefile, .cmake:
            return configRules(palette: palette)
        case .markdown, .latex:
            return markdownRules(palette: palette)
        case .sql, .graphql:
            return sqlRules(palette: palette)
        case .diff:
            return diffRules(palette: palette)
        case .log:
            return logRules(palette: palette)
        default:
            return []
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

    private static func diffRules(palette: SparkleThemePalette) -> [HighlightRule] {
        [
            HighlightRule(pattern: "^\\+.*$", hexColor: palette.stringHex, options: [.anchorsMatchLines]),
            HighlightRule(pattern: "^-.*$", hexColor: palette.accentHex, options: [.anchorsMatchLines]),
            HighlightRule(pattern: "^@@.*@@", hexColor: palette.keywordHex, options: [.anchorsMatchLines]),
            HighlightRule(
                pattern: "^(diff|index|--- |\\+\\+\\+ ).*$",
                hexColor: palette.functionHex,
                options: [.anchorsMatchLines]
            )
        ]
    }

    private static func cssRules(palette: SparkleThemePalette) -> [HighlightRule] {
        [
            HighlightRule(pattern: "[.#]?[A-Za-z0-9_-]+(?=\\s*\\{)", hexColor: palette.keywordHex, options: []),
            HighlightRule(pattern: "[A-Za-z-]+(?=\\s*:)", hexColor: palette.functionHex, options: []),
            HighlightRule(pattern: ":\\s*[^;{}]+", hexColor: palette.stringHex, options: []),
            HighlightRule(pattern: "#[0-9a-fA-F]{3,8}\\b", hexColor: palette.numberHex, options: []),
            HighlightRule(pattern: "/\\*[\\s\\S]*?\\*/", hexColor: palette.secondaryTextHex, options: [])
        ]
    }

    private static func scriptingRules(
        language: EditorSyntaxLanguage,
        palette: SparkleThemePalette
    ) -> [HighlightRule] {
        let scriptKeywords = "\\b(def|class|import|from|as|return|if|elif|else|for|while|"
            + "try|except|finally|raise|with|yield|lambda|in|not|and|or|is|None|True|False|"
            + "sub|my|our|local|function|end|then|do|repeat|until|break|echo|set|export)\\b"
        let multiStr = "\"\"\"[\\s\\S]*?\"\"\"|'''[\\s\\S]*?'''|\"([^\"\\\\]|\\\\.)*\"|'[^']*'"
        return [
            HighlightRule(pattern: scriptKeywords, hexColor: palette.keywordHex, options: []),
            HighlightRule(
                pattern: "@[A-Za-z_][A-Za-z0-9_]*|\\$[A-Za-z_{][A-Za-z0-9_}]*",
                hexColor: palette.functionHex,
                options: []
            ),
            HighlightRule(pattern: multiStr, hexColor: palette.stringHex, options: []),
            HighlightRule(pattern: "\\b\\d+(\\.\\d+)?\\b", hexColor: palette.numberHex, options: []),
            HighlightRule(pattern: "#.*$", hexColor: palette.secondaryTextHex, options: [.anchorsMatchLines])
        ]
    }

    private static func codeRules(
        language: EditorSyntaxLanguage,
        palette: SparkleThemePalette
    ) -> [HighlightRule] {
        let codeKeywords = "\\b(import|export|from|struct|class|actor|enum|protocol|interface|"
            + "type|func|function|fn|let|var|const|val|if|else|guard|return|switch|case|default|"
            + "for|while|loop|match|do|try|catch|finally|throw|throws|async|await|pub|public|"
            + "private|protected|internal|static|extension|implements|extends|trait|impl|"
            + "true|false|nil|null|undefined|self|this|new|delete)\\b"
        return [
            HighlightRule(pattern: codeKeywords, hexColor: palette.keywordHex, options: []),
            HighlightRule(
                pattern: "@[A-Za-z_][A-Za-z0-9_]*|\\$[A-Za-z_{][A-Za-z0-9_}]*",
                hexColor: palette.functionHex,
                options: []
            ),
            HighlightRule(pattern: "\"([^\"\\\\]|\\\\.)*\"|'[^']*'|`[^`]*`", hexColor: palette.stringHex, options: []),
            HighlightRule(pattern: "\\b\\d+(\\.\\d+)?\\b", hexColor: palette.numberHex, options: []),
            HighlightRule(
                pattern: "//.*$|/\\*[\\s\\S]*?\\*/",
                hexColor: palette.secondaryTextHex,
                options: [.anchorsMatchLines]
            )
        ]
    }
}
