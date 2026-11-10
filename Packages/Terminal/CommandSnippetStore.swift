import Foundation
import SparkleCore

/// Persists reusable DevOps / Sysadmin command snippets for quick injection into SSH Terminal tabs.
public actor CommandSnippetStore {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(fileURL: URL = CommandSnippetStore.defaultURL()) {
        self.fileURL = fileURL
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public static func defaultURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return appSupport
            .appendingPathComponent("SparkleSFTP", isDirectory: true)
            .appendingPathComponent("snippets.v1.json", isDirectory: false)
    }

    public static let builtInDefaults: [CommandSnippet] = [
        CommandSnippet(title: "Disk Usage", command: "df -h", category: "System"),
        CommandSnippet(
            title: "System Load & Uptime",
            command: "uptime && top -b -n 1 | head -n 15",
            category: "System"
        ),
        CommandSnippet(
            title: "Docker Containers",
            command: "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'",
            category: "Containers"
        ),
        CommandSnippet(title: "Recent System Logs", command: "journalctl -n 50 --no-pager", category: "Diagnostics"),
        CommandSnippet(title: "Listening Ports", command: "ss -tulpn", category: "Network")
    ]

    public func loadSnippets() async throws -> [CommandSnippet] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return Self.builtInDefaults
        }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode([CommandSnippet].self, from: data)
    }

    public func saveSnippets(_ snippets: [CommandSnippet]) async throws {
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try encoder.encode(snippets)
        try data.write(to: fileURL, options: [.atomic])
    }
}
