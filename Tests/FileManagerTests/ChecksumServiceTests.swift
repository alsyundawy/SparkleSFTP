import Foundation
@testable import SparkleFileManager
import Testing

@Suite("Checksum Service & Multi-Hash Digest Tests")
struct ChecksumServiceTests {
    @Test("Streaming SHA-256 and MD5 produce expected standard test vectors")
    func checksumCalculation() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sampleFile = tempDir.appendingPathComponent("test.txt")
        let content = "The quick brown fox jumps over the lazy dog"
        try Data(content.utf8).write(to: sampleFile)

        // Known SHA-256 for this standard sentence:
        // d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592
        let sha256 = try await ChecksumService.computeDigest(of: sampleFile, algorithm: .sha256)
        #expect(sha256 == "d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592")

        // Known MD5: 9e107d9d372bb6826bd81d3542a419d6
        let md5 = try await ChecksumService.computeDigest(of: sampleFile, algorithm: .md5)
        #expect(md5 == "9e107d9d372bb6826bd81d3542a419d6")
    }

    @Test("Extracts hexadecimal hash from raw remote CLI outputs")
    func extractRemoteDigest() {
        let shaOutput = "d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592  /var/log/syslog\n"
        let extracted = ChecksumService.extractDigest(from: shaOutput, algorithm: .sha256)
        #expect(extracted == "d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592")
    }
}
