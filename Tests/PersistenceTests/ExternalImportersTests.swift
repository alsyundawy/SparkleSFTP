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

    @Test("WinSCPIniImporter decodes UTF-16LE BOM, nested groups, FSProtocol, proxies, and unsupported counts")
    func winSCPIniAndUTF16Decoding() throws {
        let ini = """
        [Sessions\\Cloud%2FProd\\App%20Server]
        HostName=app.example.org
        PortNumber=2200
        UserName=ubuntu
        FSProtocol=1
        ProxyMethod=2
        ProxyHost=127.0.0.1
        ProxyPort=1080
        RemoteDirectory=/srv/app
        Password=A34F8910

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
        #expect(report.format == .winSCPINI)
        #expect(report.connections.count == 2)
        #expect(report.skippedUnsupported == 1)

        let scp = try #require(report.connections.first)
        #expect(scp.profile.protocolType == .scp)
        #expect(scp.groupName == "Cloud/Prod")
        #expect(scp.profile.name == "App Server")
        #expect(scp.profile.proxy.kind == .socks5)
        #expect(scp.secretStatus == .encryptedUnavailable)

        let ftps = try #require(report.connections.dropFirst().first)
        #expect(ftps.profile.protocolType == .ftpsImplicit)
        #expect(ftps.secretStatus == .none)
    }
}
