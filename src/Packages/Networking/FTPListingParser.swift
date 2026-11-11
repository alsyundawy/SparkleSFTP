import Foundation
import SparkleCore

/// Parses FTP `MLSD` (RFC 3659) and standard Unix `LIST -l` responses into `RemoteFile` items.
public enum FTPListingParser {
    public static func parse(listing: String, directory: RemotePath) -> [RemoteFile] {
        let lines = listing
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\r")) }
            .filter { !$0.isEmpty }

        return lines.compactMap { line in
            if line.contains(";"), let mlsd = parseMLSDLine(line, directory: directory) {
                return mlsd
            }
            return parseUnixListLine(line, directory: directory)
        }
    }

    private static func parseMLSDLine(_ line: String, directory: RemotePath) -> RemoteFile? {
        guard let spaceIdx = line.firstIndex(of: " ") else { return nil }
        let factsPart = String(line[..<spaceIdx])
        let name = String(line[line.index(after: spaceIdx)...]).trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name != ".", name != ".." else { return nil }

        var state = MLSDFactState()
        for fact in factsPart.split(separator: ";") {
            let keyValue = fact.split(separator: "=", maxSplits: 1)
            guard keyValue.count == 2 else { continue }
            guard state.apply(key: keyValue[0].lowercased(), value: String(keyValue[1])) else {
                return nil
            }
        }

        guard let itemPath = try? directory.appending(name) else { return nil }
        return RemoteFile(
            name: name,
            path: itemPath,
            size: state.size,
            isDirectory: state.isDirectory,
            permissions: state.permissions ?? (state.isDirectory ? 0o755 : 0o644),
            modificationTime: state.modDate
        )
    }

    private struct MLSDFactState {
        var isDirectory = false
        var size: Int64 = 0
        var modDate: Date?
        var permissions: UInt32?

        mutating func apply(key: String, value: String) -> Bool {
            switch key {
            case "type":
                let lower = value.lowercased()
                if lower == "cdir" || lower == "pdir" {
                    return false
                }
                isDirectory = lower == "dir"
            case "size":
                size = Int64(value) ?? 0
            case "modify":
                modDate = parseMLSDTimestamp(value)
            case "unix.mode":
                permissions = UInt32(value, radix: 8) ?? permissions
            default:
                break
            }
            return true
        }
    }

    private static func parseUnixListLine(_ line: String, directory: RemotePath) -> RemoteFile? {
        if line.lowercased().hasPrefix("total ") {
            return nil
        }
        let tokens = line.split(maxSplits: 8, omittingEmptySubsequences: true) { $0 == " " || $0 == "\t" }
        guard tokens.count == 9 else { return nil }

        let permString = String(tokens[0])
        guard permString.count >= 10 else { return nil }
        let typeChar = permString.first
        let isDir = typeChar == "d"
        let isSymlink = typeChar == "l"
        let size = Int64(tokens[4]) ?? 0

        var rawName = String(tokens[8])
        var symlinkTarget: String?
        if isSymlink, let arrowRange = rawName.range(of: " -> ") {
            symlinkTarget = String(rawName[arrowRange.upperBound...])
            rawName = String(rawName[..<arrowRange.lowerBound])
        }
        guard rawName != ".", rawName != "..", let itemPath = try? directory.appending(rawName) else {
            return nil
        }

        let permissions = parseSymbolicPermissions(permString)
        return RemoteFile(
            name: rawName,
            path: itemPath,
            size: size,
            isDirectory: isDir,
            isSymlink: isSymlink,
            symlinkTarget: symlinkTarget,
            permissions: permissions
        )
    }

    private static func parseMLSDTimestamp(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = value.contains(".") ? "yyyyMMddHHmmss.SSS" : "yyyyMMddHHmmss"
        return formatter.date(from: value)
    }

    private static func parseSymbolicPermissions(_ perm: String) -> UInt32 {
        let chars = Array(perm.dropFirst().prefix(9))
        guard chars.count == 9 else { return 0o644 }
        var mode: UInt32 = 0
        let bits: [UInt32] = [0o400, 0o200, 0o100, 0o040, 0o020, 0o010, 0o004, 0o002, 0o001]
        for (idx, char) in chars.enumerated() where char != "-" {
            mode |= bits[idx]
        }
        return mode
    }
}
