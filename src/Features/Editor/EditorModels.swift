import Foundation
import SparkleCore

public enum EditorSyntaxLanguage: String, Sendable, CaseIterable, Identifiable {
    case auto
    case plainText
    case swift
    case json
    case yaml
    case xmlHTML
    case shell
    case markdown
    case iniConfig
    case sql
    case log

    public var id: String {
        rawValue
    }

    public var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .plainText: return "Plain Text"
        case .swift: return "Swift"
        case .json: return "JSON"
        case .yaml: return "YAML"
        case .xmlHTML: return "XML / HTML"
        case .shell: return "Shell / Bash"
        case .markdown: return "Markdown"
        case .iniConfig: return "INI / Conf"
        case .sql: return "SQL"
        case .log: return "Log"
        }
    }

    private static let extensionMap: [String: EditorSyntaxLanguage] = [
        "swift": .swift,
        "json": .json,
        "appcast": .json,
        "yml": .yaml,
        "yaml": .yaml,
        "xml": .xmlHTML,
        "html": .xmlHTML,
        "htm": .xmlHTML,
        "plist": .xmlHTML,
        "entitlements": .xmlHTML,
        "svg": .xmlHTML,
        "sh": .shell,
        "bash": .shell,
        "zsh": .shell,
        "md": .markdown,
        "markdown": .markdown,
        "ini": .iniConfig,
        "conf": .iniConfig,
        "cfg": .iniConfig,
        "toml": .iniConfig,
        "env": .iniConfig,
        "properties": .iniConfig,
        "sql": .sql,
        "log": .log,
        "out": .log
    ]

    public static func detect(from filename: String) -> EditorSyntaxLanguage {
        let lower = filename.lowercased()
        let ext = (lower as NSString).pathExtension
        if let mapped = extensionMap[ext] {
            return mapped
        }
        if lower.contains("dockerfile") || lower.hasPrefix(".") {
            return .iniConfig
        }
        return .plainText
    }
}

public enum EditorLineEnding: String, Sendable, CaseIterable, Identifiable {
    case unixLF = "\n"
    case windowsCRLF = "\r\n"

    public var id: String {
        displayName
    }

    public var displayName: String {
        switch self {
        case .unixLF: return "LF"
        case .windowsCRLF: return "CRLF"
        }
    }

    public static func detect(in text: String) -> EditorLineEnding {
        text.contains("\r\n") ? .windowsCRLF : .unixLF
    }

    public static func normalize(_ text: String, to target: EditorLineEnding) -> String {
        let lfText = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return target == .windowsCRLF ? lfText.replacingOccurrences(of: "\n", with: "\r\n") : lfText
    }
}

public enum EditorTextEncoding: String, Sendable, CaseIterable, Identifiable {
    case utf8 = "UTF-8"
    case utf8BOM = "UTF-8 BOM"
    case utf16LE = "UTF-16 LE"
    case ascii = "ASCII"

    public var id: String {
        rawValue
    }

    public static func decode(_ data: Data) -> (text: String, encoding: EditorTextEncoding) {
        if data.starts(with: [0xFF, 0xFE]), let utf16 = String(bytes: data, encoding: .utf16LittleEndian) {
            return (utf16, .utf16LE)
        }
        if data.starts(with: [0xEF, 0xBB, 0xBF]),
           let utf8 = String(bytes: Data(data.dropFirst(3)), encoding: .utf8) {
            return (utf8, .utf8BOM)
        }
        if let utf8 = String(bytes: data, encoding: .utf8) {
            return (utf8, .utf8)
        }
        let fallback = String(bytes: data, encoding: .isoLatin1) ?? ""
        return (fallback, .utf8)
    }

    public func encode(_ text: String) -> Data {
        switch self {
        case .utf8:
            return Data(text.utf8)
        case .utf8BOM:
            return Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8)
        case .utf16LE:
            var out = Data([0xFF, 0xFE])
            if let encoded = text.data(using: .utf16LittleEndian) {
                out.append(encoded)
            }
            return out
        case .ascii:
            return text.data(using: .ascii, allowLossyConversion: true) ?? Data(text.utf8)
        }
    }
}

public enum EditorTextTransformKind: String, Sendable, CaseIterable {
    case uppercase
    case lowercase
    case titleCase
    case trimTrailingWhitespace
    case sortLinesAscending
    case sortLinesDescending

    public static func apply(_ kind: EditorTextTransformKind, to text: String) -> String {
        switch kind {
        case .uppercase:
            return text.uppercased()
        case .lowercase:
            return text.lowercased()
        case .titleCase:
            return text.localizedCapitalized
        case .trimTrailingWhitespace:
            return text
                .components(separatedBy: "\n")
                .map { line in
                    var end = line.endIndex
                    while end > line.startIndex {
                        let prev = line.index(before: end)
                        if line[prev] == " " || line[prev] == "\t" {
                            end = prev
                        } else {
                            break
                        }
                    }
                    return String(line[..<end])
                }
                .joined(separator: "\n")
        case .sortLinesAscending:
            return text
                .components(separatedBy: "\n")
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                .joined(separator: "\n")
        case .sortLinesDescending:
            return text
                .components(separatedBy: "\n")
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedDescending }
                .joined(separator: "\n")
        }
    }
}

public struct EditorCursorLocation: Sendable, Equatable {
    public let line: Int
    public let column: Int

    public init(line: Int = 1, column: Int = 1) {
        self.line = max(1, line)
        self.column = max(1, column)
    }

    public static func locate(in text: String, utf16Offset: Int) -> EditorCursorLocation {
        let clamped = max(0, min(utf16Offset, text.utf16.count))
        let targetIndex = text.utf16.index(text.utf16.startIndex, offsetBy: clamped)
        var line = 1
        var col = 1
        for char in text[..<targetIndex] {
            if char == "\n" {
                line += 1
                col = 1
            } else {
                col += 1
            }
        }
        return EditorCursorLocation(line: line, column: col)
    }
}

public struct EditorFindQuery: Sendable, Equatable {
    public var searchText: String
    public var replaceText: String
    public var matchCase: Bool
    public var useRegex: Bool

    public init(
        searchText: String = "",
        replaceText: String = "",
        matchCase: Bool = false,
        useRegex: Bool = false
    ) {
        self.searchText = searchText
        self.replaceText = replaceText
        self.matchCase = matchCase
        self.useRegex = useRegex
    }

    public func matchRanges(in text: String) -> [NSRange] {
        guard !searchText.isEmpty else { return [] }
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        if useRegex {
            let opts: NSRegularExpression.Options = matchCase ? [] : [.caseInsensitive]
            guard let regex = try? NSRegularExpression(pattern: searchText, options: opts) else { return [] }
            return regex.matches(in: text, options: [], range: fullRange).map(\.range)
        }
        var opts: NSString.CompareOptions = matchCase ? [] : [.caseInsensitive]
        opts.insert(.literal)
        var ranges: [NSRange] = []
        var location = 0
        while location < nsText.length {
            let searchRange = NSRange(location: location, length: nsText.length - location)
            let found = nsText.range(of: searchText, options: opts, range: searchRange)
            guard found.location != NSNotFound else { break }
            ranges.append(found)
            location = max(found.location + found.length, found.location + 1)
        }
        return ranges
    }
}

public struct EditorDocument: Identifiable, Sendable, Equatable {
    public let id: UUID
    public var title: String
    public var localURL: URL?
    public var stagingTempDir: URL?
    public var remoteProfileID: UUID?
    public var remoteHost: String?
    public var remotePath: RemotePath?
    public var content: String
    public var savedContent: String
    public var encoding: EditorTextEncoding
    public var lineEnding: EditorLineEnding
    public var syntax: EditorSyntaxLanguage
    public var isReadOnly: Bool
    public var cursor: EditorCursorLocation
    public var selectionLength: Int
    public var syncStatusKey: String
    public var isSaving: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        localURL: URL? = nil,
        stagingTempDir: URL? = nil,
        remoteProfileID: UUID? = nil,
        remoteHost: String? = nil,
        remotePath: RemotePath? = nil,
        content: String = "",
        savedContent: String? = nil,
        encoding: EditorTextEncoding = .utf8,
        lineEnding: EditorLineEnding? = nil,
        syntax: EditorSyntaxLanguage? = nil,
        isReadOnly: Bool = false
    ) {
        self.id = id
        self.title = title
        self.localURL = localURL
        self.stagingTempDir = stagingTempDir
        self.remoteProfileID = remoteProfileID
        self.remoteHost = remoteHost
        self.remotePath = remotePath
        let normalizedContent = EditorLineEnding.normalize(content, to: .unixLF)
        self.content = normalizedContent
        self.savedContent = savedContent.map { EditorLineEnding.normalize($0, to: .unixLF) } ?? normalizedContent
        self.encoding = encoding
        self.lineEnding = lineEnding ?? EditorLineEnding.detect(in: content)
        self.syntax = syntax ?? EditorSyntaxLanguage.detect(from: title)
        self.isReadOnly = isReadOnly
        cursor = EditorCursorLocation()
        selectionLength = 0
        syncStatusKey = remotePath != nil ? "editor.statusUploaded" : "editor.statusSaved"
        isSaving = false
    }

    public var isRemote: Bool {
        remotePath != nil
    }

    public var isDirty: Bool {
        content != savedContent
    }

    public var resolvedSyntax: EditorSyntaxLanguage {
        syntax == .auto ? EditorSyntaxLanguage.detect(from: title) : syntax
    }

    public var lineCount: Int {
        guard !content.isEmpty else { return 1 }
        return content.split(separator: "\n", omittingEmptySubsequences: false).count
    }

    public var byteCount: Int {
        encoding.encode(EditorLineEnding.normalize(content, to: lineEnding)).count
    }
}
