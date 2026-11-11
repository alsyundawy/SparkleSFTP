import Foundation
import SparkleCore
@testable import SparklePersistence
import Testing

@Suite("External Importer Hardening Tests")
struct ImporterHardeningTests {
    @Test("FileZillaImporter preserves directory names containing spaces and blocks malformed encodings")
    func fileZillaDirectorySpacesAndStrictEncodings() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <FileZilla3 version="3.66">
          <Servers>
            <Server>
              <Host>files.example.org</Host>
              <Port>21</Port>
              <Protocol>0</Protocol>
              <User>alice</User>
              <Pass encoding="base64">!not-valid-base64!</Pass>
              <Logontype>1</Logontype>
              <Name>Spaces Box</Name>
              <RemoteDir>1 0 6 my dir 7 sub dir</RemoteDir>
            </Server>
          </Servers>
        </FileZilla3>
        """
        let imported = try FileZillaImporter.parse(xmlData: Data(xml.utf8))
        let item = try #require(imported.first)
        #expect(item.profile.defaultRemotePath.rawValue == "/my dir/sub dir")
        #expect(item.secretStatus == .encryptedUnavailable)
        #expect(item.transientSecret == nil)
    }
}
