import Foundation
import SparkleCore

/// Unified reader supporting security-scoped URLs and UTF-8 / UTF-16 BOM / Latin1 encodings.
public enum ExternalConnectionFileReader {
    public static func defaultFileZillaSiteFiles(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        var baseDirectories = [homeDirectory]
        if let realHome = FileManager.default.homeDirectory(forUser: NSUserName()),
           realHome.path != homeDirectory.path {
            baseDirectories.append(realHome)
        }

        var candidates: [URL] = []
        for base in baseDirectories {
            candidates.append(contentsOf: [
                base.appendingPathComponent(".config/filezilla/sitemanager.xml"),
                base.appendingPathComponent(".config/filezilla/filezilla.xml"),
                base.appendingPathComponent(".config/filezilla/recentservers.xml"),
                base.appendingPathComponent(".filezilla/sitemanager.xml"),
                base.appendingPathComponent(".filezilla/filezilla.xml"),
                base.appendingPathComponent(".filezilla/recentservers.xml"),
                base.appendingPathComponent("Library/Preferences/FileZilla/sitemanager.xml"),
                base.appendingPathComponent("Library/Preferences/FileZilla/filezilla.xml"),
                base.appendingPathComponent("Library/Preferences/FileZilla/recentservers.xml"),
                base.appendingPathComponent("Library/Application Support/filezilla/sitemanager.xml"),
                base.appendingPathComponent("Library/Application Support/filezilla/filezilla.xml")
            ])
        }
        var seen = Set<String>()
        return candidates.filter { url in
            let path = url.path
            guard !seen.contains(path), FileManager.default.fileExists(atPath: path) else { return false }
            seen.insert(path)
            return true
        }
    }

    public static func defaultWinSCPSiteFiles(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        var baseDirectories = [homeDirectory]
        if let realHome = FileManager.default.homeDirectory(forUser: NSUserName()),
           realHome.path != homeDirectory.path {
            baseDirectories.append(realHome)
        }

        var candidates: [URL] = []
        for base in baseDirectories {
            candidates.append(contentsOf: [
                base.appendingPathComponent("WinSCP.ini"),
                base.appendingPathComponent("winscp.ini"),
                base.appendingPathComponent(".winscp.ini"),
                base.appendingPathComponent("Downloads/WinSCP.ini"),
                base.appendingPathComponent("Downloads/winscp.ini"),
                base.appendingPathComponent("Documents/WinSCP.ini"),
                base.appendingPathComponent("Documents/winscp.ini"),
                base.appendingPathComponent("Desktop/WinSCP.ini"),
                base.appendingPathComponent("Desktop/winscp.ini"),
                base.appendingPathComponent(".config/winscp/winscp.ini"),
                base.appendingPathComponent(".config/winscp/WinSCP.ini"),
                base.appendingPathComponent("Library/Application Support/WinSCP/WinSCP.ini"),
                base.appendingPathComponent("Library/Application Support/WinSCP/winscp.ini"),
                base.appendingPathComponent(".wine/drive_c/Program Files (x86)/WinSCP/WinSCP.ini"),
                base.appendingPathComponent(".wine/drive_c/Program Files/WinSCP/WinSCP.ini")
            ])
        }
        var seen = Set<String>()
        return candidates.filter { url in
            let path = url.path
            guard !seen.contains(path), FileManager.default.fileExists(atPath: path) else { return false }
            seen.insert(path)
            return true
        }
    }

    public static func decodeText(from data: Data) -> String {
        if data.starts(with: [0xFF, 0xFE]),
           let utf16LE = String(bytes: Data(data.dropFirst(2)), encoding: .utf16LittleEndian) {
            return utf16LE
        }
        if data.starts(with: [0xFE, 0xFF]),
           let utf16BE = String(bytes: Data(data.dropFirst(2)), encoding: .utf16BigEndian) {
            return utf16BE
        }
        var utf8Data = data
        if utf8Data.starts(with: [0xEF, 0xBB, 0xBF]) {
            utf8Data = Data(utf8Data.dropFirst(3))
        }
        if let utf8 = String(bytes: utf8Data, encoding: .utf8) {
            return utf8
        }
        return String(bytes: data, encoding: .windowsCP1252)
            ?? String(bytes: data, encoding: .isoLatin1)
            ?? ""
    }

    public static func inspect(url: URL) throws -> ExternalImportReport {
        let didScope = url.startAccessingSecurityScopedResource()
        defer {
            if didScope {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let data = try Data(contentsOf: url)
        return try inspect(data: data, fileExtension: url.pathExtension.lowercased())
    }

    public static func inspect(data: Data, fileExtension: String) throws -> ExternalImportReport {
        let text = decodeText(from: data)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if fileExtension == "xml" || trimmed.hasPrefix("<") {
            return try FileZillaImporter.parseWithReport(xmlData: data)
        }
        if fileExtension == "sparklesftp" || fileExtension == "json" || trimmed.hasPrefix("{") {
            if InternalConnectionExporter.isEncryptedArchive(data: data) {
                return ExternalImportReport(
                    format: .encryptedArchive,
                    connections: [],
                    skippedUnsupported: 0,
                    warnings: ["ARCHIVE_ENCRYPTED_PASSPHRASE_REQUIRED"]
                )
            }
            if InternalConnectionExporter.isNativeExport(data: data) {
                return try InternalConnectionExporter.parseToReport(data: data, passphrase: nil)
            }
        }
        return IniSessionImporter.parseWithReport(iniContents: text)
    }
}
