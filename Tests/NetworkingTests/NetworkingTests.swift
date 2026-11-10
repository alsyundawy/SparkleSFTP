import Foundation
import NIOCore
import SparkleCore
@testable import SparkleNetworking
import Testing

@Suite("SparkleNetworking Tests")
struct NetworkingTests {
    @Test("SFTPPacketCodec round-trips INIT, OPEN, READ, WRITE, NAME, and STATUS binary packets")
    func sftpPacketCodecRoundTrip() throws {
        let packets: [SFTPPacket] = [
            .initialize(version: 3),
            .version(version: 3, extensions: ["posix-rename@openssh.com": "1"]),
            .open(
                requestID: 42,
                path: "/var/log/syslog",
                flags: [.read],
                attributes: SFTPAttributes(permissions: 0o644)
            ),
            .read(requestID: 43, handle: Data([0x01, 0x02]), offset: 4096, length: 65_536),
            .write(requestID: 44, handle: Data([0x01, 0x02]), offset: 0, data: Data("hello".utf8)),
            .name(
                requestID: 45,
                entries: [
                    SFTPNameEntry(
                        filename: "app.tar.gz",
                        longname: "-rw-r--r-- 1 root root 1024 app.tar.gz",
                        attributes: SFTPAttributes(
                            size: 1024,
                            uid: 0,
                            gid: 0,
                            permissions: 0o100644,
                            accessTime: 100,
                            modificationTime: 200
                        )
                    )
                ]
            ),
            .status(requestID: 46, code: .eof, message: "End of file", languageTag: "en")
        ]

        var streamBuffer = ByteBufferAllocator().buffer(capacity: 1024)
        for packet in packets {
            var encoded = SFTPPacketCodec.encode(packet)
            streamBuffer.writeBuffer(&encoded)
        }

        var decoded: [SFTPPacket] = []
        while let next = try SFTPPacketCodec.decodeNext(from: &streamBuffer) {
            decoded.append(next)
        }
        #expect(decoded == packets)
    }

    @Test("SFTPPacketCodec handles partial TCP chunks cleanly without advancing buffer")
    func sftpPacketCodecPartialFrame() throws {
        let frame = SFTPPacketCodec.encode(.status(requestID: 7, code: .succeeded, message: "OK", languageTag: ""))
        let bytes = Array(frame.readableBytesView)
        var buffer = ByteBufferAllocator().buffer(capacity: bytes.count)
        buffer.writeBytes(bytes.prefix(3))
        #expect(try SFTPPacketCodec.decodeNext(from: &buffer) == nil)
        buffer.writeBytes(bytes.dropFirst(3))
        let packet = try SFTPPacketCodec.decodeNext(from: &buffer)
        #expect(packet == .status(requestID: 7, code: .succeeded, message: "OK", languageTag: ""))
    }

    @Test("SCPCompatibilityAdapter escapes injection payloads cleanly with single quotes")
    func scpShellEscapingBlocksInjection() throws {
        let evil = "/tmp/foo'; rm -rf /; echo '$(id)'"
        let escaped = try SCPCompatibilityAdapter.escapePOSIXSingleQuoted(evil)
        #expect(escaped == "'/tmp/foo'\\''; rm -rf /; echo '\\''$(id)'\\'''")

        #expect(throws: AppError.pathTraversal(attempted: "/tmp/bad\0file")) {
            _ = try SCPCompatibilityAdapter.escapePOSIXSingleQuoted("/tmp/bad\0file")
        }
    }

    @Test("FTPListingParser parses MLSD and Unix LIST formats accurately")
    func ftpListingParserFormats() {
        let mlsd = """
        type=cdir;modify=20261111030000; .
        type=dir;modify=20261111030500;UNIX.mode=0755; releases
        type=file;size=2048;modify=20261111031000;UNIX.mode=0644; spark.dmg
        """
        let mlsdFiles = FTPListingParser.parse(listing: mlsd, directory: "/pub")
        #expect(mlsdFiles.count == 2)
        #expect(mlsdFiles[0].isDirectory)
        #expect(mlsdFiles[0].name == "releases")
        #expect(mlsdFiles[1].size == 2048)
        #expect(mlsdFiles[1].permissions == 0o644)

        let unixList = """
        total 16
        drwxr-xr-x 2 deploy staff 4096 Nov 11 03:00 config
        -rw-r----- 1 deploy staff 8192 Nov 11 03:05 app.log
        lrwxrwxrwx 1 deploy staff   11 Nov 11 03:06 current -> releases/v1
        """
        let unixFiles = FTPListingParser.parse(listing: unixList, directory: "/srv")
        #expect(unixFiles.count == 3)
        #expect(unixFiles[0].isDirectory)
        #expect(unixFiles[1].size == 8192)
        #expect(unixFiles[2].isSymlink)
        #expect(unixFiles[2].symlinkTarget == "releases/v1")
    }

    @Test("FTPService blocks CWE-93 CRLF and NUL FTP command injection paths")
    func ftpSanitizeControlPathBlocksCRLF() throws {
        #expect(try FTPService.sanitizeControlPath("/releases/v1.tar.gz") == "/releases/v1.tar.gz")
        #expect(throws: AppError.pathTraversal(attempted: "/tmp/a\r\nDELE /etc/passwd")) {
            _ = try FTPService.sanitizeControlPath("/tmp/a\r\nDELE /etc/passwd")
        }
        #expect(throws: AppError.pathTraversal(attempted: "/tmp/a\0b")) {
            _ = try FTPService.sanitizeControlPath("/tmp/a\0b")
        }
    }
}
