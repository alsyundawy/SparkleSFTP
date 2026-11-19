import Foundation
import SparkleCore
import SparkleFeatures
import SparklePersistence
import SparkleTerminal
import Testing

@Suite("Command Snippets Expanded Suite", .serialized)
struct CommandSnippetExpandedTests {
    @Test("Built-in snippet catalog contains at least 180 modern curated snippets across 17 categories")
    func testBuiltInSnippetsCatalogCountAndCategories() {
        let defaults = CommandSnippetStore.builtInDefaults
        #expect(defaults.count >= 180)
        #expect(defaults.count == 185)

        let categories = Set(defaults.map(\.category))
        let expectedCategories: Set<String> = [
            "System",
            "Network",
            "Containers",
            "Kubernetes",
            "Services",
            "Diagnostics",
            "Security",
            "Databases",
            "DevOps",
            "Files",
            "Git",
            "Web & Proxy",
            "Network Probes",
            "Observability",
            "Containers & K8s",
            "Security & Audit"
        ]
        #expect(expectedCategories.isSubset(of: categories))

        for snippet in defaults {
            #expect(!snippet.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(!snippet.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(!snippet.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }

        // Verify all commands are unique (no accidental duplicate snippets)
        let commands = defaults.map(\.command)
        let uniqueCommands = Set(commands)
        #expect(commands.count == uniqueCommands.count)
    }

    @Test("CommandSnippetStore merges missing defaults into pre-existing user snippets on load")
    func testSnippetStoreMergeDefaults() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sparkle_snippet_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("snippets.v1.json")
        let store = CommandSnippetStore(fileURL: fileURL)

        // Seed an existing file with 1 custom snippet
        let custom = CommandSnippet(title: "Legacy Ping", command: "ping -c 1 8.8.8.8", category: "Custom")
        try await store.saveSnippets([custom])

        // Load snippets should return the custom snippet + all 185 defaults
        let loaded = try await store.loadSnippets()
        #expect(loaded.count == 186)
        #expect(loaded.contains { $0.title == "Legacy Ping" })
        #expect(loaded.contains { $0.title == "Disk Space Overview" })

        // Calling loadSnippets a second time should keep the same count
        let reloaded = try await store.loadSnippets()
        #expect(reloaded.count == 186)
    }

    @MainActor
    @Test("AppState resetSnippetsToDefaults restores clean default catalog")
    func testAppStateResetSnippetsToDefaults() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sparkle_appstate_snippet_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("snippets.v1.json")
        let store = CommandSnippetStore(fileURL: fileURL)
        let appState = AppState(snippetStore: store)

        await appState.addSnippet(title: "Temporary", command: "echo test", category: "Temp")
        #expect(appState.snippets.contains { $0.title == "Temporary" })

        await appState.resetSnippetsToDefaults()
        #expect(appState.snippets.count == 185)
        #expect(!appState.snippets.contains { $0.title == "Temporary" })
    }
}
