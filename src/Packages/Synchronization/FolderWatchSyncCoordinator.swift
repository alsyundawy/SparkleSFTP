import Foundation
import SparkleCore

/// Configuration governing automated local-to-remote directory sync-on-change.
public struct FolderWatchSyncConfig: Sendable, Equatable {
    public let localURL: URL
    public let remotePath: RemotePath
    public let allowRemoteDelete: Bool
    public let exclusions: [String]
    public let debounceSeconds: TimeInterval

    public init(
        localURL: URL,
        remotePath: RemotePath,
        allowRemoteDelete: Bool = false,
        exclusions: [String] = [".git", ".DS_Store", "node_modules", "*.tmp"],
        debounceSeconds: TimeInterval = 1.5
    ) {
        self.localURL = localURL
        self.remotePath = remotePath
        self.allowRemoteDelete = allowRemoteDelete
        self.exclusions = exclusions
        self.debounceSeconds = max(0.5, debounceSeconds)
    }
}

/// Actor coordinating automated folder watch and debounced upload synchronization.
public actor FolderWatchSyncCoordinator {
    public let config: FolderWatchSyncConfig
    public private(set) var isActive = false
    public private(set) var isPaused = false
    private var pendingPaths = Set<String>()
    private var debounceTask: Task<Void, Never>?
    private let onSyncTrigger: @Sendable (Set<String>) async -> Void

    public init(
        config: FolderWatchSyncConfig,
        onSyncTrigger: @escaping @Sendable (Set<String>) async -> Void
    ) {
        self.config = config
        self.onSyncTrigger = onSyncTrigger
    }

    /// Activates watch coordinator.
    public func start() {
        guard !isActive else { return }
        isActive = true
        isPaused = false
    }

    /// Pauses sync processing (e.g. upon network disconnection).
    public func pause() {
        isPaused = true
        debounceTask?.cancel()
        debounceTask = nil
    }

    /// Resumes sync processing upon network reconnection.
    public func resume() {
        isPaused = false
        if !pendingPaths.isEmpty {
            scheduleDebounce()
        }
    }

    /// Stops coordinator and cancels all pending sync tasks.
    public func stop() {
        isActive = false
        isPaused = false
        debounceTask?.cancel()
        debounceTask = nil
        pendingPaths.removeAll()
    }

    /// Records local filesystem modification event, debouncing execution across 1.5s window.
    public func recordLocalChange(relativePath: String) {
        guard isActive, !isPaused, !isPathExcluded(relativePath) else { return }

        pendingPaths.insert(relativePath)
        scheduleDebounce()
    }

    private func scheduleDebounce() {
        debounceTask?.cancel()
        let delayNanoseconds = UInt64(config.debounceSeconds * 1_000_000_000)

        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled else { return }
            await self?.flushPendingSync()
        }
    }

    private func flushPendingSync() async {
        guard isActive, !isPaused, !pendingPaths.isEmpty else { return }
        let pathsToSync = pendingPaths
        pendingPaths.removeAll()
        await onSyncTrigger(pathsToSync)
    }

    /// Checks whether path matches any exclusion glob pattern.
    public func isPathExcluded(_ path: String) -> Bool {
        let components = path.split(separator: "/")
        for pattern in config.exclusions {
            if pattern.hasPrefix("*") {
                let suffix = String(pattern.dropFirst())
                if path.hasSuffix(suffix) {
                    return true
                }
            } else if components.contains(where: { String($0) == pattern }) {
                return true
            }
        }
        return false
    }
}
