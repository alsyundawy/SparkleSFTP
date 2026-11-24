import Foundation
import SparkleCore
import SparkleSecurity

/// Security sanitizer that parses WinSCP-style command placeholders and neutralizes CWE-78 shell injection (v0.5.0).
public enum RemoteCommandSanitizer {
    /// Replaces WinSCP placeholders:
    /// - `!/`: Remote current working directory (single-quoted)
    /// - `!`: Selected filename or path (single-quoted)
    /// - `!?<prompt>:<default>?!`: Prompt value or fallback (single-quoted)
    public static func substitutePlaceholders(
        template: String,
        selectedFile: String? = nil,
        remotePath: String? = nil,
        promptInputs: [String: String] = [:]
    ) throws -> String {
        if template.contains("\0") {
            throw AppError.maliciousCommandInjection(command: template)
        }

        // Single-pass left-to-right token substitution prevents re-scanning substituted
        // values that happen to contain `!` or `!/` (CWE-78).
        let promptRegex = try NSRegularExpression(pattern: #"!\?([^:?]+?)(?::([^?]*?))?\?!"#)
        var output = ""
        output.reserveCapacity(template.count)

        var cachedSafePath: String?
        var cachedSafeFile: String?
        var index = template.startIndex

        while index < template.endIndex {
            let nsRemaining = NSRange(index ..< template.endIndex, in: template)
            if template[index...].hasPrefix("!?"),
               let match = promptRegex.firstMatch(in: template, options: [.anchored], range: nsRemaining),
               let fullRange = Range(match.range, in: template) {
                try output.append(resolvePromptToken(match: match, in: template, promptInputs: promptInputs))
                index = fullRange.upperBound
            } else if template[index...].hasPrefix("!/") {
                if let cachedSafePath {
                    output.append(cachedSafePath)
                } else {
                    let safePath = try validateAndQuote(remotePath, placeholder: "!/", label: "remote directory")
                    cachedSafePath = safePath
                    output.append(safePath)
                }
                index = template.index(index, offsetBy: 2)
            } else if template[index] == "!" {
                if let cachedSafeFile {
                    output.append(cachedSafeFile)
                } else {
                    let safeFile = try validateAndQuote(selectedFile, placeholder: "!", label: "selected file")
                    cachedSafeFile = safeFile
                    output.append(safeFile)
                }
                index = template.index(after: index)
            } else {
                output.append(template[index])
                index = template.index(after: index)
            }
        }

        return output
    }

    private static func resolvePromptToken(
        match: NSTextCheckingResult,
        in template: String,
        promptInputs: [String: String]
    ) throws -> String {
        guard let keyRange = Range(match.range(at: 1), in: template) else {
            throw AppError.maliciousCommandInjection(command: template)
        }
        let promptKey = String(template[keyRange])
        let defaultValue: String = if match.numberOfRanges > 2,
                                      let defRange = Range(match.range(at: 2), in: template) {
            String(template[defRange])
        } else {
            ""
        }
        let rawValue = promptInputs[promptKey] ?? defaultValue
        try assertNoDangerousShellEscapes(rawValue)
        return try PathValidator.escapePOSIXSingleQuoted(rawValue)
    }

    private static func validateAndQuote(_ value: String?, placeholder: String, label: String) throws -> String {
        guard let value, !value.isEmpty else {
            throw AppError.maliciousCommandInjection(
                command: "Missing required \(label) for '\(placeholder)' placeholder"
            )
        }
        try assertNoDangerousShellEscapes(value)
        return try PathValidator.escapePOSIXSingleQuoted(value)
    }

    /// Extracts interactive prompt definitions from a template string.
    public static func extractPrompts(from template: String) -> [(prompt: String, defaultValue: String)] {
        guard let regex = try? NSRegularExpression(pattern: #"!\?([^:?]+?)(?::([^?]*?))?\?!"#) else {
            return []
        }
        let nsString = template as NSString
        let matches = regex.matches(in: template, range: NSRange(location: 0, length: nsString.length))
        var results: [(prompt: String, defaultValue: String)] = []

        for match in matches {
            let promptKey = nsString.substring(with: match.range(at: 1))
            let defaultValue: String = if match.numberOfRanges > 2, match.range(at: 2).location != NSNotFound {
                nsString.substring(with: match.range(at: 2))
            } else {
                ""
            }
            results.append((prompt: promptKey, defaultValue: defaultValue))
        }
        return results
    }

    /// Rejects malicious shell metacharacters in parameter values to eliminate command injection.
    public static func assertNoDangerousShellEscapes(_ input: String) throws {
        if input.contains("\0") {
            throw AppError.maliciousCommandInjection(command: input)
        }

        // Check for unescaped control operators and command substitutions
        let dangerousSubstrings = [";", "&&", "||", "|", "`", "$(", "${"]
        for dangerous in dangerousSubstrings where input.contains(dangerous) {
            let msg = "Input contains forbidden shell metacharacter '\(dangerous)': \(input)"
            throw AppError.maliciousCommandInjection(command: msg)
        }
    }
}
