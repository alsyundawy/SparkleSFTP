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

        var result = template

        // 1. Substitute interactive prompts: !?<prompt>:<default>?! or !?<prompt>?!
        let regex = try NSRegularExpression(pattern: #"!\?([^:?]+?)(?::([^?]*?))?\?!"#)
        let nsString = result as NSString
        let matches = regex.matches(in: result, range: NSRange(location: 0, length: nsString.length))

        for match in matches.reversed() {
            let fullRange = match.range
            let promptRange = match.range(at: 1)
            let promptKey = nsString.substring(with: promptRange)

            let defaultValue: String = if match.numberOfRanges > 2, match.range(at: 2).location != NSNotFound {
                nsString.substring(with: match.range(at: 2))
            } else {
                ""
            }

            let rawValue = promptInputs[promptKey] ?? defaultValue
            try assertNoDangerousShellEscapes(rawValue)
            let safeValue = try PathValidator.escapePOSIXSingleQuoted(rawValue)

            let targetSubstring = nsString.substring(with: fullRange)
            result = result.replacingOccurrences(of: targetSubstring, with: safeValue)
        }

        // 2. Substitute remote directory `!/` (must come before `!`)
        if result.contains("!/") {
            guard let remotePath, !remotePath.isEmpty else {
                let msg = "Missing required remote directory for '!/' placeholder"
                throw AppError.maliciousCommandInjection(command: msg)
            }
            try assertNoDangerousShellEscapes(remotePath)
            let safePath = try PathValidator.escapePOSIXSingleQuoted(remotePath)
            result = result.replacingOccurrences(of: "!/", with: safePath)
        }

        // 3. Substitute selected file `!`
        if result.contains("!") {
            guard let selectedFile, !selectedFile.isEmpty else {
                throw AppError.maliciousCommandInjection(command: "Missing required selected file for '!' placeholder")
            }
            try assertNoDangerousShellEscapes(selectedFile)
            let safeFile = try PathValidator.escapePOSIXSingleQuoted(selectedFile)
            result = result.replacingOccurrences(of: "!", with: safeFile)
        }

        return result
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
