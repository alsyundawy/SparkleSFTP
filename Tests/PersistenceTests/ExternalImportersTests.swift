import Foundation
import SparkleCore
@testable import SparklePersistence
import Testing

@Suite("External Connection Reader & Importer Tests")
struct ExternalImportersTests {
    @Test("FileZillaImporter parses folders, recent servers, base64 passwords, and flags crypt secrets")
    func fileZillaXMLNestedGroupsAndCryptProtection() throws {
        let b64Secret = Data("s3cr3t-pass".utf8).base64EncodedString()
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <FileZilla3 version="3.67.0" platform="mac">
          <Servers>
            <Folder expanded="1">Production
              <Folder expanded="1">EU-West
                <Server>
                  <Host>eu.example.com</Host>
                  <Port>2222</Port>
                  <Protocol>1</Protocol>
                  <User>deploy</User>
                  <Pass encoding="base64">\(b64Secret)</Pass>
                  <Name>EU SFTP</Name>
                  <RemoteDir>/var/www</RemoteDir>
                </Server>
                <Server>
                  <Host>crypt.example.com</Host>
                  <Port>21</Port>
                  <Protocol>4</Protocol>
                  <User>ftpsuser</User>
                  <Pass encoding="crypt" pubkey="master">deadbeef</Pass>
                  <Name>Protected FTPS</Name>
                </Server>
              </Folder>
            </Folder>
          </Servers>
        </FileZilla3>
        """
        let report = try FileZillaImporter.parseWithReport(xmlData: Data(xml.utf8))
        #expect(report.format == .fileZillaXML)
        #expect(report.connections.count == 2)

        let first = try #require(report.connections.first)
        #expect(first.profile.protocolType == .sftp)
        #expect(first.profile.port == 2222)
        #expect(first.groupName == "Production / EU-West")
        #expect(first.secretStatus == .plaintextReady)
        #expect(first.transientSecret == Data("s3cr3t-pass".utf8))

        let second = try #require(report.connections.dropFirst().first)
        #expect(second.profile.protocolType == .ftpsExplicit)
        #expect(second.secretStatus == .encryptedUnavailable)
        #expect(second.transientSecret == nil)
    }

    @Test("IniSessionImporter decodes UTF-16LE BOM, nested groups, FSProtocol, proxies, and unsupported counts")
    func commanderIniAndUTF16Decoding() throws {
        let ini = """
        [Sessions\\Cloud%2FProd\\App%20Server]
        HostName=app.example.org
        PortNumber=2200
        UserName=ubuntu
        FSProtocol=0
        ProxyMethod=2
        ProxyHost=127.0.0.1
        ProxyPort=1080
        RemoteDirectory=/srv/app
        Password=A34F8910

        [Sessions\\Default%20SFTP]
        HostName=sftp.example.org
        UserName=ubuntu
        FSProtocol=1

        [Sessions\\Legacy%20FTPS]
        HostName=ftp.example.org
        PortNumber=990
        UserName=archiver
        FSProtocol=5
        Ftps=1

        [Sessions\\Unsupported%20S3]
        HostName=s3.amazonaws.com
        UserName=bucket
        FSProtocol=7
        """
        var bomData = Data([0xFF, 0xFE])
        if let utf16 = ini.data(using: .utf16LittleEndian) {
            bomData.append(utf16)
        }
        let report = try ExternalConnectionFileReader.inspect(data: bomData, fileExtension: "ini")
        #expect(report.format == .commanderINI)
        #expect(report.connections.count == 3)
        #expect(report.skippedUnsupported == 1)

        let scp = try #require(report.connections.first)
        #expect(scp.profile.protocolType == .scp)
        #expect(scp.groupName == "Cloud/Prod")
        #expect(scp.profile.name == "App Server")
        #expect(scp.profile.proxy.kind == .socks5)
        #expect(scp.secretStatus == .encryptedUnavailable)

        let defaultSFTP = try #require(report.connections.dropFirst().first)
        #expect(defaultSFTP.profile.protocolType == .sftp)

        let ftps = try #require(report.connections.dropFirst(2).first)
        #expect(ftps.profile.protocolType == .ftpsImplicit)
        #expect(ftps.secretStatus == .none)
    }

    @Test("IniSessionImporter decrypts standard UTF-8 passwords and legacy obfuscated passwords safely")
    func commanderIniPasswordDecryption() throws {
        let unicodeSecret = "p@ssw0rd!€123"
        let encryptedStandard = Self.encodeStandardIniPassword(
            password: unicodeSecret,
            username: "alice@corp",
            hostname: "files.example.org"
        )
        let encryptedUserless = Self.encodeStandardIniPassword(
            password: "anon-secret",
            username: "",
            hostname: "public.example.net"
        )
        let encryptedLegacy = Self.encodeLegacyIniPassword(password: "legacy42")

        let ini = """
        [Configuration\\Security]
        UseMasterPassword=0

        [Sessions\\Prod\\Unicode%20SFTP]
        HostName=files.example.org
        PortNumber=22
        UserName=alice%40corp
        FSProtocol=0
        Password=\(encryptedStandard)

        [Sessions\\PublicFTP]
        HostName=public.example.net
        FSProtocol=5
        Password=\(encryptedUserless)

        [Sessions\\OldHost]
        HostName=old.example.org
        UserName=ops
        FSProtocol=1
        Password=\(encryptedLegacy)
        """
        let report = try ExternalConnectionFileReader.inspect(data: Data(ini.utf8), fileExtension: "ini")
        #expect(report.connections.count == 3)

        let stdEntry = report.connections[0]
        #expect(stdEntry.profile.username == "alice@corp")
        #expect(stdEntry.secretStatus == .plaintextReady)
        #expect(stdEntry.transientSecret == Data(unicodeSecret.utf8))
        #expect(stdEntry.profile.passwordRef != nil)

        let anonEntry = report.connections[1]
        #expect(anonEntry.secretStatus == .plaintextReady)
        #expect(anonEntry.transientSecret == Data("anon-secret".utf8))

        let legacyEntry = report.connections[2]
        #expect(legacyEntry.secretStatus == .plaintextReady)
        #expect(legacyEntry.transientSecret == Data("legacy42".utf8))
    }

    @Test("IniSessionImporter fails closed when Vault Password is enabled or payload is corrupted")
    func commanderIniVaultPasswordFailsClosed() {
        let validWithoutVaultPass = Self.encodeStandardIniPassword(
            password: "should-not-decode-when-vault-pass-enabled",
            username: "deploy",
            hostname: "host.example.com"
        )
        let ini = """
        [Sessions\\Protected]
        HostName=host.example.com
        UserName=deploy
        FSProtocol=0
        Password=\(validWithoutVaultPass)

        [Configuration\\Security]
        UseMasterPassword=1
        """
        let report = IniSessionImporter.parseWithReport(iniContents: ini)
        #expect(report.connections.count == 1)
        #expect(report.connections[0].secretStatus == .encryptedUnavailable)
        #expect(report.connections[0].transientSecret == nil)
        #expect(report.connections[0].profile.passwordRef == nil)
    }

    private static func encodeObfuscatedByte(_ plain: UInt8) -> String {
        let obfuscated = ~plain ^ 0xA3
        return String(format: "%02X", obfuscated)
    }

    private static func encodeStandardIniPassword(
        password: String,
        username: String,
        hostname: String
    ) -> String {
        let payload = Array((username + hostname + password).utf8)
        let shift = 3
        var hex = encodeObfuscatedByte(0xFF)
            + encodeObfuscatedByte(0x00)
            + encodeObfuscatedByte(UInt8(payload.count))
            + encodeObfuscatedByte(UInt8(shift))
        for pad in 0 ..< shift {
            hex += encodeObfuscatedByte(UInt8((pad * 37 + 11) & 0xFF))
        }
        for byte in payload {
            hex += encodeObfuscatedByte(byte)
        }
        return hex
    }

    private static func encodeLegacyIniPassword(password: String) -> String {
        let payload = Array(password.utf8)
        let shift = 2
        var hex = encodeObfuscatedByte(UInt8(payload.count)) + encodeObfuscatedByte(UInt8(shift))
        for pad in 0 ..< shift {
            hex += encodeObfuscatedByte(UInt8((pad + 19) & 0xFF))
        }
        for byte in payload {
            hex += encodeObfuscatedByte(byte)
        }
        return hex
    }
}
