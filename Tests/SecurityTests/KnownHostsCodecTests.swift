import Foundation
import SparkleCore
import SparkleSecurity
import Testing

@Suite("OpenSSH Known Hosts Codec & Sync Tests")
struct KnownHostsCodecTests {
    @Test("KnownHostsCodec parses plain host entries and extracts fingerprints")
    func testParsePlainHostEntries() {
        let sample = """
        # This is a comment
        github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl comment1
        [192.168.1.10]:2222 ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBN/1
        """

        let parsed = KnownHostsCodec.parse(contents: sample)
        #expect(parsed.count == 2)
        #expect(parsed[0].hostPattern == "github.com")
        #expect(parsed[0].keyType == "ssh-ed25519")
        #expect(parsed[0].comment == "comment1")
        #expect(parsed[0].fingerprintSHA256.hasPrefix("SHA256:"))

        #expect(parsed[1].hostPattern == "[192.168.1.10]:2222")
        #expect(parsed[1].keyType == "ecdsa-sha2-nistp256")
    }

    @Test("KnownHostsCodec matches plain and port-specific host patterns")
    func testHostMatching() {
        #expect(KnownHostsCodec.matches(pattern: "example.com", host: "example.com", port: 22))
        #expect(KnownHostsCodec.matches(pattern: "example.com,192.168.1.1", host: "192.168.1.1", port: 22))
        #expect(KnownHostsCodec.matches(pattern: "[example.com]:2222", host: "example.com", port: 2222))
        #expect(!KnownHostsCodec.matches(pattern: "[example.com]:2222", host: "example.com", port: 22))
    }

    @Test("KnownHostsCodec formats entries with and without comments")
    func testFormatting() {
        let dummyData = Data([0x01, 0x02, 0x03, 0x04])
        let standard = KnownHostsCodec.format(
            host: "server.local",
            port: 22,
            keyType: "ssh-ed25519",
            keyData: dummyData
        )
        #expect(standard.hasPrefix("server.local ssh-ed25519 "))

        let portSpecific = KnownHostsCodec.format(
            host: "server.local",
            port: 2200,
            keyType: "ssh-ed25519",
            keyData: dummyData,
            comment: "production"
        )
        #expect(portSpecific.hasPrefix("[server.local]:2200 ssh-ed25519 "))
        #expect(portSpecific.hasSuffix("production"))
    }
}
