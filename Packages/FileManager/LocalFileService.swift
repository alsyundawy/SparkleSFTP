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
        let keys: [URLResourceKey] = [
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
            .contentModificationDateKey
        ]
        let options: FileManager.DirectoryEnumerationOptions = showHidden ? [] : [.skipsHiddenFiles]
        let contents = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: options)

        return contents.compactMap { entryURL in
            let values = try? entryURL.resourceValues(forKeys: Set(keys))
            let attrs = try? fileManager.attributesOfItem(atPath: entryURL.path)
            let isDir = values?.isDirectory ?? false
            let isLink = values?.isSymbolicLink ?? false
            let size = Int64(values?.fileSize ?? (attrs?[.size] as? NSNumber)?.intValue ?? 0)
            let perms = (attrs?[.posixPermissions] as? NSNumber)?.uint32Value ?? (isDir ? 0o755 : 0o644)
            let mtime = values?.contentModificationDate
            let symlinkTarget = isLink ? (try? fileManager.destinationOfSymbolicLink(atPath: entryURL.path)) : nil

            return RemoteFile(
                name: entryURL.lastPathComponent,
                path: RemotePath(rawValue: entryURL.path),
                size: size,
                isDirectory: isDir,
                isSymlink: isLink,
                symlinkTarget: symlinkTarget,
                permissions: perms & 0o7777,
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
