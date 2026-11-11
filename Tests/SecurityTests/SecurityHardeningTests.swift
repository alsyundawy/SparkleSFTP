import Foundation
import SparkleCore
@testable import SparkleDesignSystem
@testable import SparkleSecurity
import Testing

@Suite("SparkleSecurity & Catalog Hardening Tests")
struct SecurityHardeningTests {
    @Test("PathValidator rejects rooted dot-dot escape paths")
    func pathValidatorRejectsRootedDotDotTraversal() throws {
        #expect(throws: AppError.pathTraversal(attempted: "/../../etc/passwd")) {
            _ = try PathValidator.canonicalizeRemote("/../../etc/passwd", relativeTo: RemotePath("/"))
        }
        #expect(throws: AppError.pathTraversal(attempted: "/srv/../../etc/passwd")) {
            _ = try PathValidator.canonicalizeRemote("/srv/../../etc/passwd", relativeTo: RemotePath("/"))
        }
    }

    @Test("LocalizationCatalog importLocaleFile blocks CWE-22 locale code path traversal")
    func localizationCatalogBlocksPathTraversalCode() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SparkleLocaleTest-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let badJSON = """
        {
          "code": "../../evil",
          "displayName": "Bad",
          "version": "1.0.0",
          "strings": { "common.ok": "OK" }
        }
        """
        let inputURL = dir.appendingPathComponent("bad.json")
        try Data(badJSON.utf8).write(to: inputURL)

        let targetDir = dir.appendingPathComponent("Locales", isDirectory: true)
        var didThrow = false
        do {
            _ = try LocalizationCatalog.importLocaleFile(from: inputURL, into: targetDir)
        } catch {
            didThrow = true
        }
        #expect(didThrow)
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("evil.json").path))
    }
}
