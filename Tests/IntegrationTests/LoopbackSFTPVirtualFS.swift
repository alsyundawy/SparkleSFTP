import Foundation
import SparkleNetworking

/// Real temp-directory backed SFTP v3 responder for loopback SSH integration tests.
final class LoopbackSFTPVirtualFS: @unchecked Sendable { // JUSTIFICATION: NSLock serializes virtual handle table.
    private let lock = NSLock()
    private let rootURL: URL
    private var nextHandleID: UInt32 = 1
    private var openFiles: [Data: FileHandle] = [:]
    private var openDirs: [Data: [SFTPNameEntry]?] = [:]

    init(rootURL: URL) throws {
        self.rootURL = rootURL
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    deinit {
        lock.lock()
        for (_, fileHandle) in openFiles {
            try? fileHandle.close()
        }
        openFiles.removeAll()
        openDirs.removeAll()
        lock.unlock()
    }

    func handle(_ packet: SFTPPacket) -> SFTPPacket {
        if case .initialize = packet {
            return .version(version: 3, extensions: [:])
        }
        let reqID = packet.requestID ?? 0
        do {
            return try dispatchPacket(packet, reqID: reqID)
        } catch {
            return .status(requestID: reqID, code: .failure, message: error.localizedDescription, languageTag: "")
        }
    }

    private func dispatchPacket(_ packet: SFTPPacket, reqID: UInt32) throws -> SFTPPacket {
        switch packet {
        case let .opendir(_, path):
            return try handleOpenDir(reqID: reqID, remotePath: path)
        case let .readdir(_, handle):
            return handleReadDir(reqID: reqID, handle: handle)
        case let .close(_, handle):
            return handleClose(reqID: reqID, handle: handle)
        case let .lstat(_, path), let .stat(_, path):
            return try handleStat(reqID: reqID, remotePath: path)
        case let .realpath(_, path):
            return handleRealpath(reqID: reqID, remotePath: path)
        case let .open(_, path, flags, _):
            return try handleOpen(reqID: reqID, remotePath: path, flags: flags)
        case let .read(_, handle, offset, length):
            return try handleRead(reqID: reqID, handle: handle, offset: offset, length: length)
        case let .write(_, handle, offset, data):
            return try handleWrite(reqID: reqID, handle: handle, offset: offset, data: data)
        default:
            return try dispatchMutation(packet, reqID: reqID)
        }
    }

    private func dispatchMutation(_ packet: SFTPPacket, reqID: UInt32) throws -> SFTPPacket {
        switch packet {
        case let .mkdir(_, path, _):
            try FileManager.default.createDirectory(at: resolveURL(path), withIntermediateDirectories: true)
            return .status(requestID: reqID, code: .succeeded, message: "OK", languageTag: "")
        case let .rmdir(_, path), let .remove(_, path):
            let url = resolveURL(path)
            guard FileManager.default.fileExists(atPath: url.path) else {
                return .status(requestID: reqID, code: .noSuchFile, message: "Missing", languageTag: "")
            }
            try FileManager.default.removeItem(at: url)
            return .status(requestID: reqID, code: .succeeded, message: "OK", languageTag: "")
        case let .rename(_, oldPath, newPath):
            let src = resolveURL(oldPath)
            let dst = resolveURL(newPath)
            if FileManager.default.fileExists(atPath: dst.path) {
                try FileManager.default.removeItem(at: dst)
            }
            try FileManager.default.moveItem(at: src, to: dst)
            return .status(requestID: reqID, code: .succeeded, message: "OK", languageTag: "")
        case let .setstat(_, path, attrs):
            if let perms = attrs.permissions {
                let targetPath = resolveURL(path).path
                try FileManager.default.setAttributes([.posixPermissions: Int(perms)], ofItemAtPath: targetPath)
            }
            return .status(requestID: reqID, code: .succeeded, message: "OK", languageTag: "")
        default:
            return .status(requestID: reqID, code: .opUnsupported, message: "Unsupported", languageTag: "")
        }
    }

    private func handleOpenDir(reqID: UInt32, remotePath: String) throws -> SFTPPacket {
        let dirURL = resolveURL(remotePath)
        let contents = try FileManager.default.contentsOfDirectory(
            at: dirURL,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        )
        let entries = try contents.map { item -> SFTPNameEntry in
            let attrs = try attributesForURL(item)
            return SFTPNameEntry(filename: item.lastPathComponent, longname: item.lastPathComponent, attributes: attrs)
        }
        let handleData = allocateHandleData()
        lock.lock()
        openDirs[handleData] = entries
        lock.unlock()
        return .handle(requestID: reqID, handle: handleData)
    }

    private func handleReadDir(reqID: UInt32, handle: Data) -> SFTPPacket {
        lock.lock()
        let pending = openDirs[handle].flatMap(\.self)
        if pending != nil {
            openDirs[handle] = [SFTPNameEntry]?.none
        }
        lock.unlock()
        if let entries = pending {
            return .name(requestID: reqID, entries: entries)
        }
        return .status(requestID: reqID, code: .eof, message: "EOF", languageTag: "")
    }

    private func handleOpen(reqID: UInt32, remotePath: String, flags: SFTPOpenFlags) throws -> SFTPPacket {
        let fileURL = resolveURL(remotePath)
        let parent = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

        let exists = FileManager.default.fileExists(atPath: fileURL.path)
        if flags.contains(.create), !exists || flags.contains(.truncate) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .status(requestID: reqID, code: .noSuchFile, message: "Missing", languageTag: "")
        }

        let fileHandle = try FileHandle(forUpdating: fileURL)
        let handleData = allocateHandleData()
        lock.lock()
        openFiles[handleData] = fileHandle
        lock.unlock()
        return .handle(requestID: reqID, handle: handleData)
    }

    private func handleRead(reqID: UInt32, handle: Data, offset: UInt64, length: UInt32) throws -> SFTPPacket {
        lock.lock()
        let fileHandle = openFiles[handle]
        lock.unlock()
        guard let fileHandle else {
            return .status(requestID: reqID, code: .failure, message: "Bad handle", languageTag: "")
        }
        try fileHandle.seek(toOffset: offset)
        let chunk = try fileHandle.read(upToCount: Int(length)) ?? Data()
        if chunk.isEmpty {
            return .status(requestID: reqID, code: .eof, message: "EOF", languageTag: "")
        }
        return .data(requestID: reqID, payload: chunk)
    }

    private func handleWrite(reqID: UInt32, handle: Data, offset: UInt64, data: Data) throws -> SFTPPacket {
        lock.lock()
        let fileHandle = openFiles[handle]
        lock.unlock()
        guard let fileHandle else {
            return .status(requestID: reqID, code: .failure, message: "Bad handle", languageTag: "")
        }
        try fileHandle.seek(toOffset: offset)
        try fileHandle.write(contentsOf: data)
        return .status(requestID: reqID, code: .succeeded, message: "OK", languageTag: "")
    }

    private func handleClose(reqID: UInt32, handle: Data) -> SFTPPacket {
        lock.lock()
        let fileHandle = openFiles.removeValue(forKey: handle)
        openDirs.removeValue(forKey: handle)
        lock.unlock()
        try? fileHandle?.close()
        return .status(requestID: reqID, code: .succeeded, message: "Closed", languageTag: "")
    }

    private func handleStat(reqID: UInt32, remotePath: String) throws -> SFTPPacket {
        let url = resolveURL(remotePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .status(requestID: reqID, code: .noSuchFile, message: "Missing", languageTag: "")
        }
        return try .attrs(requestID: reqID, attributes: attributesForURL(url))
    }

    private func handleRealpath(reqID: UInt32, remotePath: String) -> SFTPPacket {
        let normalized = remotePath.isEmpty ? "/" : remotePath
        let entry = SFTPNameEntry(filename: normalized, longname: normalized, attributes: SFTPAttributes())
        return .name(requestID: reqID, entries: [entry])
    }

    private func resolveURL(_ remotePath: String) -> URL {
        let components = remotePath.split(separator: "/").map(String.init).filter { $0 != "." && $0 != ".." }
        return components.reduce(rootURL) { $0.appendingPathComponent($1) }
    }

    private func attributesForURL(_ url: URL) throws -> SFTPAttributes {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let isDir = (attrs[.type] as? FileAttributeType) == .typeDirectory
        let posix = (attrs[.posixPermissions] as? NSNumber)?.uint32Value ?? (isDir ? 0o755 : 0o644)
        let mode = (isDir ? UInt32(0o040000) : UInt32(0o100000)) | (posix & 0o7777)
        let size = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
        let mod = UInt32((attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)
        return SFTPAttributes(size: size, permissions: mode, accessTime: mod, modificationTime: mod)
    }

    private func allocateHandleData() -> Data {
        lock.lock()
        var current = nextHandleID.bigEndian
        nextHandleID &+= 1
        lock.unlock()
        return Data(bytes: &current, count: 4)
    }
}
