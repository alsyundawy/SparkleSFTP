import Foundation
import SparkleCore
@testable import SparkleFileManager
import Testing

@Suite("ArchiveService Zip-Slip & Symlink Traversal Tests")
struct ArchiveServiceTraversalTests {
    @Test("inspectArchiveEntries allows safe archives and blocks Zip-Slip traversal components")
    func inspectArchiveEntriesBlocksTraversal() throws {
        let baseName = "SparkleArchive-\(UUID().uuidString)"
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(baseName)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileA = tempDir.appendingPathComponent("sample.txt")
        try Data("safe content".utf8).write(to: fileA)

        let archiveURL = tempDir.appendingPathComponent("safe.tar.gz")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-czf", archiveURL.path, "-C", tempDir.path, "sample.txt"]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)

        let entries = try ArchiveService.inspectArchiveEntries(archiveURL: archiveURL)
        #expect(entries.contains("sample.txt"))

        let evilArchive = tempDir.appendingPathComponent("evil.tar.gz")
        let script = """
        import io, sys, tarfile
        with tarfile.open(sys.argv[1], 'w:gz') as tf:
            for name in ('foo/../escape.txt', '/etc/evil.txt'):
                info = tarfile.TarInfo(name)
                info.size = 1
                tf.addfile(info, io.BytesIO(b'x'))
        """
        let pythonProcess = Process()
        pythonProcess.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        pythonProcess.arguments = ["-c", script, evilArchive.path]
        try pythonProcess.run()
        pythonProcess.waitUntilExit()
        #expect(pythonProcess.terminationStatus == 0)

        #expect(throws: AppError.self) {
            _ = try ArchiveService.inspectArchiveEntries(archiveURL: evilArchive)
        }
    }

    @Test("validateExtractedSymlinksAndSize rejects sibling-prefix symlink escape and compress/extract roundtrips")
    func validateSiblingPrefixAndRoundtrip() async throws {
        let baseName = "SparkleArchiveRT-\(UUID().uuidString)"
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(baseName)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let subDir = tempDir.appendingPathComponent("extracted", isDirectory: true)
        let siblingDir = tempDir.appendingPathComponent("extracted-evil", isDirectory: true)
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: siblingDir, withIntermediateDirectories: true)
        let siblingSecret = siblingDir.appendingPathComponent("secret.txt")
        try Data("secret".utf8).write(to: siblingSecret)

        let siblingLink = subDir.appendingPathComponent("sibling_link")
        try FileManager.default.createSymbolicLink(atPath: siblingLink.path, withDestinationPath: siblingSecret.path)

        #expect(throws: AppError.self) {
            try ArchiveService.validateExtractedSymlinksAndSize(in: subDir)
        }
        #expect(!FileManager.default.fileExists(atPath: siblingLink.path))

        let srcFile = tempDir.appendingPathComponent("payload.txt")
        try Data("roundtrip-ok".utf8).write(to: srcFile)
        let bundle = tempDir.appendingPathComponent("bundle.tar.gz")
        try await ArchiveService.compress(sourceURLs: [srcFile], destinationURL: bundle, format: .tarGz)
        try await ArchiveService.extract(archiveURL: bundle, destinationDirectory: subDir)
        let outText = try String(contentsOf: subDir.appendingPathComponent("payload.txt"), encoding: .utf8)
        #expect(outText == "roundtrip-ok")
    }

    @Test("validateExtractedSymlinksAndSize catches symlink escaping extraction directory (CVE-2026-57233)")
    func validateSymlinkEscapingThrowsAndRemoves() throws {
        let baseName = "SparkleSymlink-\(UUID().uuidString)"
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(baseName)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let subDir = tempDir.appendingPathComponent("extracted", isDirectory: true)
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)

        let maliciousLink = subDir.appendingPathComponent("escape_link")
        try FileManager.default.createSymbolicLink(atPath: maliciousLink.path, withDestinationPath: "/etc/passwd")

        #expect(throws: AppError.self) {
            try ArchiveService.validateExtractedSymlinksAndSize(in: subDir)
        }
        #expect(!FileManager.default.fileExists(atPath: maliciousLink.path))
    }

    @Test("validateExtractedSymlinksAndSize allows safe relative symlinks within directory")
    func validateSafeSymlinksPasses() throws {
        let baseName = "SparkleSymlinkSafe-\(UUID().uuidString)"
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(baseName)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let subDir = tempDir.appendingPathComponent("extracted", isDirectory: true)
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)

        let targetFile = subDir.appendingPathComponent("target.txt")
        try Data("hello world".utf8).write(to: targetFile)

        let safeLink = subDir.appendingPathComponent("safe_link")
        try FileManager.default.createSymbolicLink(atPath: safeLink.path, withDestinationPath: "target.txt")

        try ArchiveService.validateExtractedSymlinksAndSize(in: subDir)
        #expect(FileManager.default.fileExists(atPath: safeLink.path))
    }
}
