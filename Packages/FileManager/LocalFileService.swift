import Darwin
import Foundation
import SparkleCore

/// Descriptor-safe filesystem watcher guaranteeing clean cancellation and zero FD leaks on pane close (RUN-005).
public final class LocalDirectoryWatcher: @unchecked Sendable { // JUSTIFICATION: NSLock + serial queue.
    private let lock = NSLock()
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private let queue = DispatchQueue(label: "com.alsyundawy.SparkleSFTP.localwatcher")

    public init() {}

    deinit {
        stopWatching()
    }

    public func startWatching(directory url: URL, onChange: @escaping @Sendable () -> Void) {
        stopWatching()
        let fileDesc = open(url.path, O_EVTONLY)
        guard fileDesc >= 0 else { return }

        let dispatchSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDesc,
            eventMask: [.write, .delete, .rename, .attrib],
            queue: queue
        )
        dispatchSource.setEventHandler {
            onChange()
        }
        dispatchSource.setCancelHandler {
            close(fileDesc)
        }

        lock.lock()
        fileDescriptor = fileDesc
        source = dispatchSource
        lock.unlock()

        dispatchSource.resume()
    }

    public func stopWatching() {
        lock.lock()
        let activeSource = source
        source = nil
        fileDescriptor = -1
        lock.unlock()

        activeSource?.cancel()
    }
}

/// Local macOS file operations mapped onto `RemoteFile` entries for unified Dual-Pane Commander UI.
public actor LocalFileService {
    private let fileManager = FileManager.default

    public init() {}

    public func listDirectory(at url: URL, showHidden: Bool = false) async throws -> [RemoteFile] {
        let options: FileManager.DirectoryEnumerationOptions = showHidden ? [] : [.skipsHiddenFiles]
        let contents = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: options)

        return contents.compactMap { entryURL in
            let pathString = entryURL.path
            var statBuf = stat()
            guard lstat(pathString, &statBuf) == 0 else { return nil }
            let fileType = statBuf.st_mode & S_IFMT
            let isDir = fileType == S_IFDIR
            let isLink = fileType == S_IFLNK
            let size = Int64(statBuf.st_size)
            let perms = UInt32(statBuf.st_mode) & 0o7777
            let mtime = Date(
                timeIntervalSince1970: TimeInterval(statBuf.st_mtimespec.tv_sec)
                    + TimeInterval(statBuf.st_mtimespec.tv_nsec) / 1_000_000_000.0
            )
            let symlinkTarget = isLink ? (try? fileManager.destinationOfSymbolicLink(atPath: pathString)) : nil

            return RemoteFile(
                name: entryURL.lastPathComponent,
                path: RemotePath(rawValue: pathString),
                size: size,
                isDirectory: isDir,
                isSymlink: isLink,
                symlinkTarget: symlinkTarget,
                permissions: perms,
                modificationTime: mtime
            )
        }
    }

    public func createDirectory(named name: String, in parent: URL) throws -> URL {
        let target = parent.appendingPathComponent(name, isDirectory: true)
        try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
        return target
    }

    public func rename(itemAt url: URL, to newName: String) throws -> URL {
        let destination = url.deletingLastPathComponent().appendingPathComponent(newName)
        try fileManager.moveItem(at: url, to: destination)
        return destination
    }

    public func delete(itemAt url: URL) throws {
        try fileManager.removeItem(at: url)
    }

    public func copy(itemAt source: URL, to destination: URL) throws {
        try fileManager.copyItem(at: source, to: destination)
    }

    public func setPermissions(_ mode: UInt32, at url: URL) throws {
        try fileManager.setAttributes([.posixPermissions: NSNumber(value: mode & 0o7777)], ofItemAtPath: url.path)
    }
}
