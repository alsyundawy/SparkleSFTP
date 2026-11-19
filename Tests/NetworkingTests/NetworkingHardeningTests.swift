import Foundation
import NIOCore
import SparkleCore
@testable import SparkleNetworking
import Testing

@Suite("Networking Codec & Compression Hardening Tests")
struct NetworkingHardeningTests {
    @Test("SFTPPacketCodec consumes 0x80000000 extended attributes without stream desync")
    func sftpCodecConsumesExtendedAttributes() throws {
        var payload = ByteBufferAllocator().buffer(capacity: 128)
        payload.writeInteger(UInt8(SFTPPacketType.name.rawValue))
        payload.writeInteger(UInt32(99))
        payload.writeInteger(UInt32(1))
        let name = Data("file.txt".utf8)
        let long = Data("-rw-r--r-- 1 u g 0 file.txt".utf8)
        payload.writeInteger(UInt32(name.count))
        payload.writeBytes(name)
        payload.writeInteger(UInt32(long.count))
        payload.writeBytes(long)
        // Flags: size (0x1) | extended (0x80000000)
        payload.writeInteger(UInt32(0x8000_0001))
        payload.writeInteger(UInt64(123))
        payload.writeInteger(UInt32(1))
        let extKey = Data("custom@vendor".utf8)
        let extVal = Data("value".utf8)
        payload.writeInteger(UInt32(extKey.count))
        payload.writeBytes(extKey)
        payload.writeInteger(UInt32(extVal.count))
        payload.writeBytes(extVal)

        var wire = ByteBufferAllocator().buffer(capacity: 256)
        wire.writeInteger(UInt32(payload.readableBytes))
        wire.writeBuffer(&payload)
        var followUp = SFTPPacketCodec.encode(.status(requestID: 100, code: .eof, message: "EOF", languageTag: ""))
        wire.writeBuffer(&followUp)

        let first = try SFTPPacketCodec.decodeNext(from: &wire)
        let second = try SFTPPacketCodec.decodeNext(from: &wire)
        #expect(second == .status(requestID: 100, code: .eof, message: "EOF", languageTag: ""))
        if case let .name(reqID, entries) = first {
            #expect(reqID == 99)
            #expect(entries.first?.attributes.size == 123)
        } else {
            Issue.record("Expected decoded NAME packet")
        }
    }

    @Test("FTPListingParser decodes S and T permission bits accurately")
    func ftpListingParserPreservesSetuidStickyBits() {
        let listing = "drwsr-Sr-T 2 root wheel 512 Nov 11 03:00 shared"
        let items = FTPListingParser.parse(listing: listing, directory: "/srv")
        #expect(items.count == 1)
        #expect(items[0].permissions == 0o7744)
    }

    @Test("ZlibCompressionCodec inflates payload matching exact maxOutputBytes limit")
    func zlibExactMaxOutputBoundary() throws {
        let raw = Data(repeating: 0x5A, count: 1024)
        let gzipData = try ZlibCompressionCodec.compress(raw, format: .gzip)
        let inflated = try ZlibCompressionCodec.decompress(gzipData, maxOutputBytes: 1024)
        #expect(inflated == raw)

        #expect(throws: AppError.self) {
            _ = try ZlibCompressionCodec.decompress(gzipData, maxOutputBytes: 1023)
        }
    }

    @Test("CurlClientHelper locks allowed protocols strictly to ftp,ftps (CVE-2025-15224)")
    func curlClientHelperRestrictsProtocols() {
        #expect(CurlClientHelper.kAllowedProtocols == "ftp,ftps")
    }

    @Test("SSHServerAuditor flags OpenSSH 8.5p1–9.7p1 as vulnerable to CVE-2024-6387 regreSSHion")
    func sshServerAuditorFlagsRegreSSHionVersions() {
        let vulnBanners = [
            "SSH-2.0-OpenSSH_8.5p1 Ubuntu-3ubuntu0.1",
            "SSH-2.0-OpenSSH_8.9p1 Debian-1",
            "SSH-2.0-OpenSSH_9.3p1",
            "SSH-2.0-OpenSSH_9.7p1"
        ]
        for banner in vulnBanners {
            let report = SSHServerAuditor.audit(banner: banner)
            #expect(report.isVulnerableToCVE20246387 == true, "Expected vulnerable: \(banner)")
            #expect(report.advisoryMessage != nil)
        }

        let safeBanners = [
            "SSH-2.0-OpenSSH_8.4p1",
            "SSH-2.0-OpenSSH_9.8p1",
            "SSH-2.0-OpenSSH_9.9p1",
            "SSH-2.0-OpenSSH_10.3p1",
            "SSH-2.0-dropbear_2020.81"
        ]
        for banner in safeBanners {
            let report = SSHServerAuditor.audit(banner: banner)
            #expect(report.isVulnerableToCVE20246387 == false, "Expected safe: \(banner)")
            #expect(report.advisoryMessage == nil)
        }
    }
}
