import Foundation
import SparkleCore

/// Safe, sandboxed Lua-style macro execution engine for the Sparkle internal editor (Task 12.2).
/// Strictly eliminates sandbox escape vectors (CVE-2026-42214) by disallowing os, io, and process invocation.
public enum EditorMacroEngine {
    public struct MacroResult: Sendable, Equatable {
        public let outputText: String
        public let selectionText: String
        public let logMessages: [String]
        public let zoomDelta: CGFloat
        public let isSuccess: Bool
        public let errorMessage: String?

        public init(
            outputText: String,
            selectionText: String = "",
            logMessages: [String] = [],
            zoomDelta: CGFloat = 0,
            isSuccess: Bool = true,
            errorMessage: String? = nil
        ) {
            self.outputText = outputText
            self.selectionText = selectionText
            self.logMessages = logMessages
            self.zoomDelta = zoomDelta
            self.isSuccess = isSuccess
            self.errorMessage = errorMessage
        }
    }

    public struct MacroPreset: Identifiable, Sendable {
        public let id: String
        public let name: String
        public let summary: String
        public let script: String

        public init(id: String, name: String, summary: String, script: String) {
            self.id = id
            self.name = name
            self.summary = summary
            self.script = script
        }
    }

    private static let forbiddenKeywords: [String] = [
        "os.execute", "os.remove", "os.rename", "os.exit", "os.getenv",
        "io.open", "io.popen", "io.read", "io.write", "io.lines",
        "package.loadlib", "package.seeall", "require", "dofile", "loadfile",
        "process", "spawn", "posix", "shell", "eval", "system"
    ]

    /// Evaluates a macro script against an active document text.
    public static func execute(
        script: String,
        initialText: String,
        selection: String = "",
        cursorLine: Int = 1
    ) -> MacroResult {
        let trimmedScript = script.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedScript.isEmpty else {
            return MacroResult(outputText: initialText, selectionText: selection, logMessages: ["Empty macro script"])
        }

        // 1. Strict Sandbox Validation (CVE-2026-42214)
        let lowerScript = script.lowercased()
        for forbidden in forbiddenKeywords where lowerScript.contains(forbidden) {
            return MacroResult(
                outputText: initialText,
                selectionText: selection,
                logMessages: ["Security Alert: Forbidden symbol '\(forbidden)' rejected by sandbox."],
                isSuccess: false,
                errorMessage: "Security Error: Sandbox escape attempt blocked (\(forbidden))."
            )
        }

        var ctx = ExecutionContext(text: initialText, selection: selection, cursorLine: cursorLine)
        let lines = script.components(separatedBy: .newlines)
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("--"), !line.hasPrefix("//"), !line.hasPrefix("#") else {
                continue
            }
            processLine(line: line, context: &ctx)
        }

        return MacroResult(
            outputText: ctx.text,
            selectionText: ctx.selection,
            logMessages: ctx.logs,
            zoomDelta: ctx.zoom,
            isSuccess: true,
            errorMessage: nil
        )
    }

    fileprivate struct ExecutionContext {
        var text: String
        var selection: String
        var zoom: CGFloat = 0
        var cursorLine: Int
        var logs: [String] = []
    }
}

// MARK: - Script Processing Pipeline
private extension EditorMacroEngine {
    static func processLine(line: String, context: inout ExecutionContext) {
        if line.hasPrefix("print(") && line.hasSuffix(")") {
            context.logs.append(extractArgument(from: line, prefix: "print("))
            return
        }
        if handleMutation(line: line, context: &context) {
            return
        }
        if handleTransform(line: line, context: &context) {
            return
        }
        if handleCodec(line: line, context: &context) {
            return
        }
        context.logs.append("executed: \(line)")
    }

    static func handleMutation(line: String, context: inout ExecutionContext) -> Bool {
        if line.hasPrefix("editor.setText(") && line.hasSuffix(")") {
            context.text = extractArgument(from: line, prefix: "editor.setText(")
            context.logs.append("setText: updated (\(context.text.count) chars)")
            return true
        }
        if line.hasPrefix("editor.replaceSelection(") && line.hasSuffix(")") {
            let arg = extractArgument(from: line, prefix: "editor.replaceSelection(")
            let resolved = resolveNestedCalls(arg, text: context.text, selection: context.selection)
            if !context.selection.isEmpty, let range = context.text.range(of: context.selection) {
                context.text.replaceSubrange(range, with: resolved)
            } else {
                context.text += resolved
            }
            context.selection = resolved
            context.logs.append("replaceSelection: updated (\(resolved.count) chars)")
            return true
        }
        if line.hasPrefix("editor.insertText(") && line.hasSuffix(")") {
            let arg = extractArgument(from: line, prefix: "editor.insertText(")
            context.text += arg
            context.logs.append("insertText: appended (\(arg.count) chars)")
            return true
        }
        return false
    }

    static func handleTransform(line: String, context: inout ExecutionContext) -> Bool {
        switch line {
        case "editor.clear()":
            context.text = ""
            context.selection = ""
            context.logs.append("clear: buffer emptied")
            return true
        case "editor.zoomIn()":
            context.zoom += 1.0
            context.logs.append("zoomIn: font size increased")
            return true
        case "editor.zoomOut()":
            context.zoom -= 1.0
            context.logs.append("zoomOut: font size decreased")
            return true
        case "editor.upper()", "editor.toUpperCase()":
            applyCaseTransform(context: &context, uppercase: true)
            return true
        case "editor.lower()", "editor.toLowerCase()":
            applyCaseTransform(context: &context, uppercase: false)
            return true
        case "editor.sortLines()":
            let sorted = context.text.components(separatedBy: .newlines).sorted()
            context.text = sorted.joined(separator: "\n")
            context.logs.append("sortLines: sorted ascending (\(sorted.count) lines)")
            return true
        case "editor.sortLinesDesc()":
            let sortedDesc = context.text.components(separatedBy: .newlines).sorted { $0 > $1 }
            context.text = sortedDesc.joined(separator: "\n")
            context.logs.append("sortLinesDesc: sorted descending (\(sortedDesc.count) lines)")
            return true
        default:
            return false
        }
    }

    static func applyCaseTransform(context: inout ExecutionContext, uppercase: Bool) {
        if !context.selection.isEmpty, let range = context.text.range(of: context.selection) {
            let transformed = uppercase ? context.selection.uppercased() : context.selection.lowercased()
            context.text.replaceSubrange(range, with: transformed)
            context.selection = transformed
        } else {
            context.text = uppercase ? context.text.uppercased() : context.text.lowercased()
        }
        context.logs.append(uppercase ? "upper: transformed" : "lower: transformed")
    }

    static func handleCodec(line: String, context: inout ExecutionContext) -> Bool {
        switch line {
        case "editor.dedup()":
            var seen = Set<String>()
            var deduped: [String] = []
            for item in context.text.components(separatedBy: .newlines) where !seen.contains(item) {
                seen.insert(item)
                deduped.append(item)
            }
            context.text = deduped.joined(separator: "\n")
            context.logs.append("dedup: retained (\(deduped.count) unique lines)")
            return true
        case "editor.numberLines()":
            let numbered = context.text.components(separatedBy: .newlines).enumerated().map { idx, line in
                line.isEmpty ? "" : "\(idx + 1). \(line)"
            }
            context.text = numbered.joined(separator: "\n")
            context.logs.append("numberLines: numbered (\(numbered.count) lines)")
            return true
        case "editor.trim()":
            let trimmed = context.text.components(separatedBy: .newlines).map {
                $0.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
            }
            context.text = trimmed.joined(separator: "\n")
            context.logs.append("trim: trailing spaces removed")
            return true
        case "editor.jsonPrettify()":
            applyJSONPrettify(context: &context)
            return true
        case "editor.base64Encode()":
            applyBase64(context: &context, encode: true)
            return true
        case "editor.base64Decode()":
            applyBase64(context: &context, encode: false)
            return true
        default:
            return false
        }
    }

    static func applyJSONPrettify(context: inout ExecutionContext) {
        guard let data = context.text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(
                  withJSONObject: json,
                  options: [.prettyPrinted, .sortedKeys]
              ),
              let prettyString = String(data: prettyData, encoding: .utf8) else {
            context.logs.append("jsonPrettify: invalid JSON content")
            return
        }
        context.text = prettyString
        context.logs.append("jsonPrettify: formatting applied successfully")
    }

    static func applyBase64(context: inout ExecutionContext, encode: Bool) {
        let target = context.selection.isEmpty ? context.text : context.selection
        if encode {
            let encoded = Data(target.utf8).base64EncodedString()
            replaceOrSet(targetText: encoded, context: &context)
            context.logs.append("base64Encode: encoded (\(encoded.count) chars)")
        } else {
            let cleaned = target.trimmingCharacters(in: .whitespacesAndNewlines)
            if let data = Data(base64Encoded: cleaned), let decoded = String(data: data, encoding: .utf8) {
                replaceOrSet(targetText: decoded, context: &context)
                context.logs.append("base64Decode: decoded successfully")
            } else {
                context.logs.append("base64Decode: invalid base64 data")
            }
        }
    }

    static func replaceOrSet(targetText: String, context: inout ExecutionContext) {
        if !context.selection.isEmpty, let range = context.text.range(of: context.selection) {
            context.text.replaceSubrange(range, with: targetText)
            context.selection = targetText
        } else {
            context.text = targetText
        }
    }

    static func extractArgument(from line: String, prefix: String) -> String {
        guard line.hasPrefix(prefix), line.hasSuffix(")") else { return "" }
        let startIndex = line.index(line.startIndex, offsetBy: prefix.count)
        let endIndex = line.index(before: line.endIndex)
        var raw = String(line[startIndex..<endIndex]).trimmingCharacters(in: .whitespaces)
        if (raw.hasPrefix("'") && raw.hasSuffix("'")) || (raw.hasPrefix("\"") && raw.hasSuffix("\"")) {
            raw.removeFirst()
            raw.removeLast()
        }
        return raw
    }

    static func resolveNestedCalls(_ expression: String, text: String, selection: String) -> String {
        let trimmed = expression.trimmingCharacters(in: .whitespaces)
        if trimmed == "editor.getSelection()" {
            return selection
        }
        if trimmed == "editor.getText()" {
            return text
        }
        if trimmed.hasPrefix("editor.upper(") && trimmed.hasSuffix(")") {
            let inner = extractArgument(from: trimmed, prefix: "editor.upper(")
            return resolveNestedCalls(inner, text: text, selection: selection).uppercased()
        }
        if trimmed.hasPrefix("editor.lower(") && trimmed.hasSuffix(")") {
            let inner = extractArgument(from: trimmed, prefix: "editor.lower(")
            return resolveNestedCalls(inner, text: text, selection: selection).lowercased()
        }
        return trimmed
    }
}

// MARK: - Built-in Presets
extension EditorMacroEngine {
    public static let builtInPresets: [MacroPreset] = [
        MacroPreset(
            id: "upper_selection",
            name: "Uppercase Selection",
            summary: "Transforms currently selected text to UPPERCASE",
            script: "editor.replaceSelection(editor.upper(editor.getSelection()))\nprint('Selection uppercased')"
        ),
        MacroPreset(
            id: "lower_selection",
            name: "Lowercase Selection",
            summary: "Transforms currently selected text to lowercase",
            script: "editor.replaceSelection(editor.lower(editor.getSelection()))\nprint('Selection lowercased')"
        ),
        MacroPreset(
            id: "sort_lines_asc",
            name: "Sort Lines Ascending",
            summary: "Sorts all lines in alphabetical ascending order",
            script: "editor.sortLines()\nprint('Lines sorted A-Z')"
        ),
        MacroPreset(
            id: "sort_lines_desc",
            name: "Sort Lines Descending",
            summary: "Sorts all lines in alphabetical descending order",
            script: "editor.sortLinesDesc()\nprint('Lines sorted Z-A')"
        ),
        MacroPreset(
            id: "dedup_lines",
            name: "Deduplicate Lines",
            summary: "Removes duplicate adjacent and non-adjacent lines",
            script: "editor.dedup()\nprint('Duplicate lines removed')"
        ),
        MacroPreset(
            id: "number_lines",
            name: "Number Lines",
            summary: "Prefaces each non-empty line with a sequential line number",
            script: "editor.numberLines()\nprint('Lines numbered')"
        ),
        MacroPreset(
            id: "trim_trailing",
            name: "Trim Trailing Whitespace",
            summary: "Strips trailing spaces and tabs from every line",
            script: "editor.trim()\nprint('Trailing whitespace stripped')"
        ),
        MacroPreset(
            id: "json_prettify",
            name: "Prettify JSON",
            summary: "Parses and indents JSON payload with 2 spaces",
            script: "editor.jsonPrettify()\nprint('JSON formatted')"
        ),
        MacroPreset(
            id: "base64_encode",
            name: "Base64 Encode",
            summary: "Encodes selection or full text to standard Base64",
            script: "editor.base64Encode()\nprint('Text encoded to Base64')"
        ),
        MacroPreset(
            id: "base64_decode",
            name: "Base64 Decode",
            summary: "Decodes valid Base64 back into plain text",
            script: "editor.base64Decode()\nprint('Base64 decoded')"
        )
    ]
}
