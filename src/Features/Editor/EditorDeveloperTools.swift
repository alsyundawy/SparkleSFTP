import CryptoKit
import Foundation
import SparkleCore

/// High-performance developer & security text utilities ported from NotepadMac (Task 12.3).
public enum EditorDeveloperTools: Sendable {
    public enum ToolKind: String, CaseIterable, Identifiable, Sendable {
        case base64Encode = "Base64 Encode"
        case base64Decode = "Base64 Decode"
        case urlEncode = "URL Percent Encode"
        case urlDecode = "URL Percent Decode"
        case jsonPrettyPrint = "JSON Pretty Print"
        case jsonMinify = "JSON Minify"
        case sha256 = "SHA-256 Digest"
        case sha512 = "SHA-512 Digest"
        case md5 = "MD5 Digest"
        case unixToISO8601 = "Unix Epoch to ISO8601"
        case iso8601ToUnix = "ISO8601 to Unix Epoch"
        case deduplicateLines = "Remove Duplicate Lines"
        case removeEmptyLines = "Remove Empty Lines"

        public var id: String { rawValue }
    }

    public static func execute(_ tool: ToolKind, on input: String) throws -> String {
        switch tool {
        case .base64Encode, .base64Decode, .urlEncode, .urlDecode:
            return try executeEncoding(tool, input: input)
        case .jsonPrettyPrint, .jsonMinify:
            return try executeJSON(tool, input: input)
        case .sha256, .sha512, .md5:
            return executeCrypto(tool, input: input)
        case .unixToISO8601, .iso8601ToUnix:
            return try executeTimestamp(tool, input: input)
        case .deduplicateLines, .removeEmptyLines:
            return executeLineTransforms(tool, input: input)
        }
    }

    private static func executeEncoding(_ tool: ToolKind, input: String) throws -> String {
        switch tool {
        case .base64Encode:
            return Data(input.utf8).base64EncodedString()
        case .base64Decode:
            let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let data = Data(base64Encoded: trimmed) else {
                throw AppError.invalidConfiguration("Invalid Base64 input string")
            }
            guard let string = String(data: data, encoding: .utf8) else {
                throw AppError.invalidConfiguration("Decoded data is not valid UTF-8 text")
            }
            return string
        case .urlEncode:
            return input.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? input
        case .urlDecode:
            guard let decoded = input.removingPercentEncoding else {
                throw AppError.invalidConfiguration("Invalid percent-encoded string")
            }
            return decoded
        default:
            return input
        }
    }

    private static func executeJSON(_ tool: ToolKind, input: String) throws -> String {
        guard let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else {
            throw AppError.invalidConfiguration("Input is not valid JSON")
        }
        let options: JSONSerialization.WritingOptions = tool == .jsonPrettyPrint
            ? [.prettyPrinted, .sortedKeys]
            : [.sortedKeys]
        let outData = try JSONSerialization.data(withJSONObject: json, options: options)
        return String(data: outData, encoding: .utf8) ?? input
    }

    private static func executeCrypto(_ tool: ToolKind, input: String) -> String {
        let data = Data(input.utf8)
        switch tool {
        case .sha256:
            return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        case .sha512:
            return SHA512.hash(data: data).map { String(format: "%02x", $0) }.joined()
        case .md5:
            return Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
        default:
            return input
        }
    }

    private static func executeTimestamp(_ tool: ToolKind, input: String) throws -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if tool == .unixToISO8601 {
            guard let epoch = Double(trimmed) else {
                throw AppError.invalidConfiguration("Expected numeric Unix timestamp")
            }
            let seconds = epoch > 100_000_000_000 ? epoch / 1000.0 : epoch
            return ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: seconds))
        }
        guard let date = ISO8601DateFormatter().date(from: trimmed) else {
            throw AppError.invalidConfiguration("Expected ISO8601 timestamp string")
        }
        return String(Int64(date.timeIntervalSince1970))
    }

    private static func executeLineTransforms(_ tool: ToolKind, input: String) -> String {
        if tool == .deduplicateLines {
            var seen = Set<String>()
            var unique: [String] = []
            for line in input.components(separatedBy: "\n") where seen.insert(line).inserted {
                unique.append(line)
            }
            return unique.joined(separator: "\n")
        }
        return input
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
    }
}
