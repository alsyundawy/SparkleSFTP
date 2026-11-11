import Foundation

/// A normalized, strongly-typed POSIX remote filesystem path.
public struct RemotePath: Sendable, Hashable, Codable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            self.rawValue = "/"
            return
        }

        let prefixed = trimmed.hasPrefix("/") ? trimmed : "/" + trimmed
        self.rawValue = Self.normalizeLexical(prefixed)
    }

    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }

    public var isRoot: Bool {
        rawValue == "/"
    }

    public var isAbsolute: Bool {
        rawValue.hasPrefix("/")
    }

    public var filename: String {
        guard !isRoot else { return "/" }
        return URL(fileURLWithPath: rawValue).lastPathComponent
    }

    public var parent: RemotePath {
        guard !isRoot else { return RemotePath(rawValue: "/") }
        let parentPath = URL(fileURLWithPath: rawValue).deletingLastPathComponent().path
        return RemotePath(rawValue: parentPath.isEmpty ? "/" : parentPath)
    }

    public var description: String {
        rawValue
    }

    public func appending(_ component: String) throws -> RemotePath {
        if component.contains("\0") {
            throw AppError.pathTraversal(attempted: component)
        }
        let cleaned = component.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !cleaned.isEmpty else { return self }
        if cleaned == ".." || cleaned.split(separator: "/").contains("..") {
            throw AppError.pathTraversal(attempted: component)
        }
        if rawValue == "/" {
            return RemotePath(rawValue: "/" + cleaned)
        }
        return RemotePath(rawValue: rawValue + "/" + cleaned)
    }

    /// Lexically collapses repeated slashes and `.` segments while preserving leading `/`.
    /// Relative `..` segments are resolved safely clamped at `/`.
    public static func normalizeLexical(_ path: String) -> String {
        var components: [Substring] = []
        for segment in path.split(separator: "/", omittingEmptySubsequences: true) {
            switch segment {
            case ".":
                continue
            case "..":
                if !components.isEmpty {
                    components.removeLast()
                }
            default:
                components.append(segment)
            }
        }
        if components.isEmpty {
            return "/"
        }
        return "/" + components.joined(separator: "/")
    }
}
