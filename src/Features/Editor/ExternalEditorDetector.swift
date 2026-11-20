import AppKit
import Foundation
import SparkleCore

/// Represents an external code/text editor available on macOS.
public struct ExternalEditorApp: Identifiable, Sendable, Equatable {
    public let id: String
    public let displayName: String
    public let bundleIdentifier: String
    public let binaryName: String?
    public let waitFlag: String?
    public let appURL: URL?
    public let isInstalled: Bool

    public init(
        id: String,
        displayName: String,
        bundleIdentifier: String,
        binaryName: String? = nil,
        waitFlag: String? = nil,
        appURL: URL? = nil,
        isInstalled: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
        self.binaryName = binaryName
        self.waitFlag = waitFlag
        self.appURL = appURL
        self.isInstalled = isInstalled
    }
}

/// Auto-discovery and execution service for external desktop editors.
public enum ExternalEditorDetector {
    /// Registry of supported external text editors on macOS.
    public static let knownEditors: [ExternalEditorApp] = [
        ExternalEditorApp(
            id: "vscode",
            displayName: "Visual Studio Code",
            bundleIdentifier: "com.microsoft.VSCode",
            binaryName: "code",
            waitFlag: "--wait"
        ),
        ExternalEditorApp(
            id: "vscode-insiders",
            displayName: "Visual Studio Code Insiders",
            bundleIdentifier: "com.microsoft.VSCodeInsiders",
            binaryName: "code-insiders",
            waitFlag: "--wait"
        ),
        ExternalEditorApp(
            id: "sublime",
            displayName: "Sublime Text",
            bundleIdentifier: "com.sublimetext.4",
            binaryName: "subl",
            waitFlag: "--wait"
        ),
        ExternalEditorApp(
            id: "bbedit",
            displayName: "BBEdit",
            bundleIdentifier: "com.barebones.bbedit",
            binaryName: "bbedit",
            waitFlag: "--wait"
        ),
        ExternalEditorApp(
            id: "textmate",
            displayName: "TextMate",
            bundleIdentifier: "com.macromates.TextMate",
            binaryName: "mate",
            waitFlag: "--wait"
        ),
        ExternalEditorApp(
            id: "coteditor",
            displayName: "CotEditor",
            bundleIdentifier: "com.coteditor.CotEditor",
            binaryName: "cot",
            waitFlag: "-w"
        ),
        ExternalEditorApp(
            id: "macvim",
            displayName: "MacVim",
            bundleIdentifier: "org.vim.MacVim",
            binaryName: "mvim",
            waitFlag: "-f"
        ),
        ExternalEditorApp(
            id: "notepadmac",
            displayName: "NotepadMac",
            bundleIdentifier: "com.alsyundawy.NotepadMac"
        ),
        ExternalEditorApp(
            id: "sparknotepad",
            displayName: "SparkNotePad",
            bundleIdentifier: "com.alsyundawy.SparkNotePad"
        ),
        ExternalEditorApp(
            id: "cursor",
            displayName: "Cursor",
            bundleIdentifier: "com.todesktop.230313mzl4w4u92",
            binaryName: "cursor",
            waitFlag: "--wait"
        )
    ]

    /// Probes macOS workspace and `/Applications` to detect installed editors.
    @MainActor
    public static func detectInstalledEditors() -> [ExternalEditorApp] {
        let workspace = NSWorkspace.shared
        return knownEditors.map { editor in
            let resolvedURL = workspace.urlForApplication(withBundleIdentifier: editor.bundleIdentifier)
            let installed = resolvedURL != nil
            return ExternalEditorApp(
                id: editor.id,
                displayName: editor.displayName,
                bundleIdentifier: editor.bundleIdentifier,
                binaryName: editor.binaryName,
                waitFlag: editor.waitFlag,
                appURL: resolvedURL,
                isInstalled: installed
            )
        }
    }

    /// Resolves preferred editor matching saved path or falls back to first detected editor.
    public static func resolveEditor(
        savedPath: String?,
        available: [ExternalEditorApp]
    ) -> ExternalEditorApp? {
        if let saved = savedPath, !saved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let lower = saved.lowercased()
            if let matched = available.first(where: {
                $0.appURL?.path.lowercased() == lower ||
                    $0.displayName.lowercased() == lower ||
                    $0.id.lowercased() == lower
            }) {
                return matched
            }
        }
        return available.first(where: { $0.isInstalled })
    }

    /// Builds command-line arguments including wait flags (`--wait`, `-w`, etc.) for synchronous editing.
    public static func buildCLIArguments(for editor: ExternalEditorApp, filePath: String) -> [String] {
        var args: [String] = []
        if let flag = editor.waitFlag {
            args.append(flag)
        }
        args.append(filePath)
        return args
    }
}
