import Foundation
import SparkleCore

/// Thread-safe file-system watcher monitoring external edits using Darwin DispatchSource (CWE-59 / CWE-367).
public final class ExternalEditWatcher:
    @unchecked Sendable { // JUSTIFICATION: Coordinated via internal NSLock and serial DispatchQueue.
    private let session: ExternalEditSession
    private let onChange: @Sendable (ExternalEditSession) -> Void
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var debounceWorkItem: DispatchWorkItem?
    private let queue = DispatchQueue(label: "com.alsyundawy.SparkleSFTP.ExternalEditWatcher", qos: .utility)
    private let lock = NSLock()
    private var isCancelled = false

    public init(session: ExternalEditSession, onChange: @escaping @Sendable (ExternalEditSession) -> Void) {
        self.session = session
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    /// Starts monitoring the session's local cache file for external modifications.
    public func start() {
        lock.lock()
        defer { lock.unlock() }
        guard fileDescriptor == -1, !isCancelled else { return }

        // O_EVTONLY | O_NOFOLLOW: Event monitoring only, rejects symlink traversal (CWE-59)
        let openedFD = open(session.localCacheURL.path, O_EVTONLY | O_NOFOLLOW)
        guard openedFD >= 0 else { return }
        fileDescriptor = openedFD

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: openedFD,
            eventMask: [.write, .extend, .attrib, .rename],
            queue: queue
        )

        src.setEventHandler { [weak self] in
            self?.scheduleDebouncedChange()
        }

        src.setCancelHandler {
            close(openedFD)
        }

        source = src
        src.resume()
    }

    /// Cancels file system source and safely closes the file descriptor.
    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        guard !isCancelled else { return }
        isCancelled = true
        debounceWorkItem?.cancel()
        debounceWorkItem = nil

        if let src = source {
            source = nil
            src.cancel()
        }
        fileDescriptor = -1
    }

    private func scheduleDebouncedChange() {
        lock.lock()
        defer { lock.unlock() }
        guard !isCancelled else { return }

        debounceWorkItem?.cancel()
        let sessionRef = session
        let callback = onChange

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, !self.isCancelled else { return }
            if sessionRef.hasLocalChanges() {
                DispatchQueue.main.async {
                    callback(sessionRef)
                }
            }
        }
        debounceWorkItem = workItem
        queue.asyncAfter(deadline: .now() + .milliseconds(500), execute: workItem)
    }
}
