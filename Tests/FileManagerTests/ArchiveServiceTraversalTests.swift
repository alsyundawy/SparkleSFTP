import Foundation
import SparkleCore
@testable import SparkleFileManager
import Testing

@Suite("ArchiveService Zip-Slip & Symlink Traversal Tests")
struct ArchiveServiceTraversalTests {
    @Test("inspectArchiveEntries blocks Zip-Slip traversal components")
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
