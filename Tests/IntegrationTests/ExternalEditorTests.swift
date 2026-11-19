import Foundation
import SparkleCore
@testable import SparkleFeatures
import Testing

@Suite("External Editor Discovery & Integration Tests")
struct ExternalEditorTests {
    @Test("ExternalEditorDetector registry includes major macOS code and text editors")
    func testRegistryIntegrity() {
        let editors = ExternalEditorDetector.knownEditors
        #expect(editors.count >= 8)

        let vscode = editors.first(where: { $0.id == "vscode" })
        #expect(vscode?.displayName == "Visual Studio Code")
        #expect(vscode?.waitFlag == "--wait")
        #expect(vscode?.binaryName == "code")

        let bbedit = editors.first(where: { $0.id == "bbedit" })
        #expect(bbedit?.displayName == "BBEdit")
        #expect(bbedit?.waitFlag == "--wait")

        let coteditor = editors.first(where: { $0.id == "coteditor" })
        #expect(coteditor?.waitFlag == "-w")
    }

    @Test("ExternalEditorDetector builds proper CLI arguments with wait flags")
    func testCLIArgumentBuilding() {
        let vscode = ExternalEditorApp(
            id: "vscode",
            displayName: "VS Code",
            bundleIdentifier: "com.microsoft.VSCode",
            binaryName: "code",
            waitFlag: "--wait"
        )
        let args = ExternalEditorDetector.buildCLIArguments(for: vscode, filePath: "/tmp/config.yml")
        #expect(args == ["--wait", "/tmp/config.yml"])

        let plain = ExternalEditorApp(
            id: "notepadmac",
            displayName: "NotepadMac",
            bundleIdentifier: "com.alsyundawy.NotepadMac"
        )
        let plainArgs = ExternalEditorDetector.buildCLIArguments(for: plain, filePath: "/tmp/notes.txt")
        #expect(plainArgs == ["/tmp/notes.txt"])
    }

    @Test("ExternalEditorDetector resolves editor by saved configuration path")
    func testResolveEditor() {
        let testEditors = [
            ExternalEditorApp(
                id: "sublime",
                displayName: "Sublime Text",
                bundleIdentifier: "com.sublimetext.4",
                appURL: URL(fileURLWithPath: "/Applications/Sublime Text.app"),
                isInstalled: true
            ),
            ExternalEditorApp(
                id: "vscode",
                displayName: "Visual Studio Code",
                bundleIdentifier: "com.microsoft.VSCode",
                appURL: URL(fileURLWithPath: "/Applications/Visual Studio Code.app"),
                isInstalled: false
            )
        ]

        let resolved = ExternalEditorDetector.resolveEditor(
            savedPath: "/Applications/Sublime Text.app",
            available: testEditors
        )
        #expect(resolved?.id == "sublime")

        let fallback = ExternalEditorDetector.resolveEditor(savedPath: nil, available: testEditors)
        #expect(fallback?.id == "sublime")
    }
}
