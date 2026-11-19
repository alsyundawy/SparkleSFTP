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

    @Test("ExternalEditSession detects cache tampering and inode substitution")
    func testCacheIntegrity() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("EditIntegrity-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appendingPathComponent("doc.txt")
        try Data("content".utf8).write(to: file)
        let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
        let inode = (attrs[.systemFileNumber] as? UInt64) ?? 12345

        let baseline = ExternalEditBaseline(
            localMtime: Date(),
            localSize: 7,
            localSHA256: "hash",
            remoteMtime: Date(),
            remoteSize: 7,
            localInode: inode
        )
        let remoteFile = RemoteFile(name: "doc.txt", path: RemotePath("/doc.txt"), size: 7, isDirectory: false)
        let session = ExternalEditSession(
            remoteFile: remoteFile,
            localCacheURL: file,
            sessionDirectoryURL: dir,
            baseline: baseline
        )
        #expect(session.verifyCacheIntegrity() == true)

        let badBaseline = ExternalEditBaseline(
            localMtime: Date(),
            localSize: 7,
            localSHA256: "hash",
            remoteMtime: Date(),
            remoteSize: 7,
            localInode: inode + 999
        )
        let badSession = ExternalEditSession(
            remoteFile: remoteFile,
            localCacheURL: file,
            sessionDirectoryURL: dir,
            baseline: badBaseline
        )
        #expect(badSession.verifyCacheIntegrity() == false)
    }
}
