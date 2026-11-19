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

    public static let builtInDefaults: [CommandSnippet] =
        systemSnippets +
        networkSnippets +
        containerSnippets +
        kubernetesSnippets +
        serviceSnippets +
        diagnosticSnippets +
        securitySnippets +
        databaseSnippets +
        devopsSnippets +
        fileSnippets +
        gitSnippets +
        webServerSnippets +
        networkProbesSnippets +
        observabilitySnippets +
        containerOrchestrationSnippets +
        databaseCloudSnippets +
        systemHardeningSnippets

    public func loadSnippets() async throws -> [CommandSnippet] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return Self.builtInDefaults
        }
        let data = try Data(contentsOf: fileURL)
        let loaded = try decoder.decode([CommandSnippet].self, from: data)
        var existingCommands = Set(loaded.map(\.command))
        var merged = loaded
        for def in Self.builtInDefaults where !existingCommands.contains(def.command) {
            merged.append(def)
            existingCommands.insert(def.command)
        }
        if merged.count != loaded.count {
            try? await saveSnippets(merged)
        }
        return merged
    }

    public func resetToDefaults() async throws -> [CommandSnippet] {
        let defaults = Self.builtInDefaults
        try await saveSnippets(defaults)
        return defaults
    }

    public func saveSnippets(_ snippets: [CommandSnippet]) async throws {
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try encoder.encode(snippets)
        try data.write(to: fileURL, options: [.atomic])
    }
}
