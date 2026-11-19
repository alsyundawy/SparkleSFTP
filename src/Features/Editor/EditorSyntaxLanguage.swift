import Foundation

public enum EditorSyntaxLanguage: String, Sendable, CaseIterable, Identifiable {
    case auto
    case plainText
    case swift
    case cLanguage = "c"
    case cpp
    case objectiveC
    case rust
    case golang = "go"
    case java
    case kotlin
    case csharp
    case scala
    case dart
    case python
    case ruby
    case perl
    case php
    case lua
    case rLanguage = "r"
    case julia
    case javascript
    case typescript
    case jsx
    case tsx
    case vue
    case svelte
    case html
    case css
    case scss
    case less
    case shell
    case zsh
    case fish
    case powershell
    case batch
    case sql
    case graphql
    case json
    case yaml
    case toml
    case xmlHTML
    case iniConfig
    case properties
    case dockerfile
    case nginx
    case apache
    case makefile
    case cmake
    case markdown
    case latex
    case diff
    case log

    public var id: String {
        rawValue
    }

    private static let displayNames: [EditorSyntaxLanguage: String] = [
        .auto: "Auto",
        .plainText: "Plain Text",
        .swift: "Swift",
        .cLanguage: "C",
        .cpp: "C++",
        .objectiveC: "Objective-C",
        .rust: "Rust",
        .golang: "Go",
        .java: "Java",
        .kotlin: "Kotlin",
        .csharp: "C#",
        .scala: "Scala",
        .dart: "Dart",
        .python: "Python",
        .ruby: "Ruby",
        .perl: "Perl",
        .php: "PHP",
        .lua: "Lua",
        .rLanguage: "R",
        .julia: "Julia",
        .javascript: "JavaScript",
        .typescript: "TypeScript",
        .jsx: "React JSX",
        .tsx: "React TSX",
        .vue: "Vue",
        .svelte: "Svelte",
        .html: "HTML",
        .css: "CSS",
        .scss: "SCSS",
        .less: "LESS",
        .shell: "Shell / Bash",
        .zsh: "Zsh",
        .fish: "Fish Shell",
        .powershell: "PowerShell",
        .batch: "Batch / CMD",
        .sql: "SQL",
        .graphql: "GraphQL",
        .json: "JSON",
        .yaml: "YAML",
        .toml: "TOML",
        .xmlHTML: "XML / HTML",
        .iniConfig: "INI / Conf",
        .properties: "Properties",
        .dockerfile: "Dockerfile",
        .nginx: "Nginx",
        .apache: "Apache Conf",
        .makefile: "Makefile",
        .cmake: "CMake",
        .markdown: "Markdown",
        .latex: "LaTeX",
        .diff: "Diff / Patch",
        .log: "Log"
    ]

    public var displayName: String {
        Self.displayNames[self] ?? rawValue.capitalized
    }

    private static let extensionMap: [String: EditorSyntaxLanguage] = [
        "swift": .swift,
        "c": .cLanguage,
        "h": .cLanguage,
        "cpp": .cpp,
        "cc": .cpp,
        "cxx": .cpp,
        "hpp": .cpp,
        "hh": .cpp,
        "m": .objectiveC,
        "mm": .objectiveC,
        "rs": .rust,
        "go": .golang,
        "java": .java,
        "kt": .kotlin,
        "kts": .kotlin,
        "cs": .csharp,
        "scala": .scala,
        "sc": .scala,
        "dart": .dart,
        "py": .python,
        "pyw": .python,
        "rb": .ruby,
        "pl": .perl,
        "pm": .perl,
        "php": .php,
        "phtml": .php,
        "lua": .lua,
        "r": .rLanguage,
        "jl": .julia,
        "js": .javascript,
        "mjs": .javascript,
        "cjs": .javascript,
        "ts": .typescript,
        "jsx": .jsx,
        "tsx": .tsx,
        "vue": .vue,
        "svelte": .svelte,
        "html": .html,
        "htm": .html,
        "css": .css,
        "scss": .scss,
        "less": .less,
        "sh": .shell,
        "bash": .shell,
        "zsh": .zsh,
        "fish": .fish,
        "ps1": .powershell,
        "psm1": .powershell,
        "bat": .batch,
        "cmd": .batch,
        "sql": .sql,
        "graphql": .graphql,
        "gql": .graphql,
        "json": .json,
        "appcast": .json,
        "yml": .yaml,
        "yaml": .yaml,
        "toml": .toml,
        "xml": .xmlHTML,
        "plist": .xmlHTML,
        "entitlements": .xmlHTML,
        "svg": .xmlHTML,
        "ini": .iniConfig,
        "conf": .iniConfig,
        "cfg": .iniConfig,
        "env": .iniConfig,
        "properties": .properties,
        "dockerfile": .dockerfile,
        "makefile": .makefile,
        "mk": .makefile,
        "cmake": .cmake,
        "md": .markdown,
        "markdown": .markdown,
        "tex": .latex,
        "diff": .diff,
        "patch": .diff,
        "log": .log,
        "out": .log
    ]

    public static func detect(from filename: String, content: String? = nil) -> EditorSyntaxLanguage {
        if let shebangMatch = detectShebang(content: content) {
            return shebangMatch
        }
        return detectFromFilename(filename)
    }

    private static func detectShebang(content: String?) -> EditorSyntaxLanguage? {
        guard let content, content.hasPrefix("#!") else { return nil }
        let firstLine = content.prefix(120).lowercased()
        if firstLine.contains("python") { return .python }
        if firstLine.contains("bash") || firstLine.contains("sh") { return .shell }
        if firstLine.contains("zsh") { return .zsh }
        if firstLine.contains("perl") { return .perl }
        if firstLine.contains("ruby") { return .ruby }
        if firstLine.contains("php") { return .php }
        if firstLine.contains("node") { return .javascript }
        if firstLine.contains("lua") { return .lua }
        return nil
    }

    private static func detectFromFilename(_ filename: String) -> EditorSyntaxLanguage {
        let lower = filename.lowercased()
        if lower == "dockerfile" || lower.hasPrefix("dockerfile.") { return .dockerfile }
        if lower == "makefile" || lower == "gnumakefile" { return .makefile }
        if lower == "cmakelists.txt" { return .cmake }
        if lower.contains("nginx") { return .nginx }
        if lower.contains("httpd") || lower.contains("apache") { return .apache }
        let ext = (lower as NSString).pathExtension
        if let mapped = extensionMap[ext] {
            return mapped
        }
        if lower.hasPrefix(".") {
            return .iniConfig
        }
        return .plainText
    }
}
