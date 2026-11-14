import CryptoKit
import Foundation
import SparkleCore

/// Baseline snapshot of a remote file when first downloaded for external editing.
public struct ExternalEditBaseline: Sendable, Equatable {
    public let localMtime: Date
    public let localSize: Int64
    public let localSHA256: String
    public let remoteMtime: Date?
    public let remoteSize: Int64

    public init(
        localMtime: Date,
        localSize: Int64,
        localSHA256: String,
        remoteMtime: Date?,
        remoteSize: Int64
    ) {
        self.localMtime = localMtime
        self.localSize = localSize
        self.localSHA256 = localSHA256
        self.remoteMtime = remoteMtime
        self.remoteSize = remoteSize
    }
}

/// Represents an active external editor session watching a sandboxed cache file.
public final class ExternalEditSession: Identifiable,
    @unchecked Sendable { // JUSTIFICATION: Protected via internal NSLock.
    public let id: UUID
    public let remoteFile: RemoteFile
    public let localCacheURL: URL
    public let sessionDirectoryURL: URL
    public let baseline: ExternalEditBaseline
    public let appBundleIdentifier: String?
    public private(set) var isTerminated: Bool = false
    private let lock = NSLock()

    public init(
        id: UUID = UUID(),
        remoteFile: RemoteFile,
        localCacheURL: URL,
        sessionDirectoryURL: URL,
        baseline: ExternalEditBaseline,
        appBundleIdentifier: String? = nil
    ) {
        self.id = id
        self.remoteFile = remoteFile
        self.localCacheURL = localCacheURL
        self.sessionDirectoryURL = sessionDirectoryURL
        self.baseline = baseline
        self.appBundleIdentifier = appBundleIdentifier
    }

    /// Evaluates whether the local cache file has changed compared to baseline.
    public func hasLocalChanges() -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: localCacheURL.path),
              let currentMtime = attrs[.modificationDate] as? Date,
              let currentSize = attrs[.size] as? Int64 else {
            return false
        }
        if abs(currentMtime.timeIntervalSince(baseline.localMtime)) < 0.5, currentSize == baseline.localSize {
            return false
        }
        guard let currentData = try? Data(contentsOf: localCacheURL) else { return false }
        let currentHash = SHA256.hash(data: currentData).map { String(format: "%02x", $0) }.joined()
        return currentHash != baseline.localSHA256
    }

    /// Safely terminates session and removes sandboxed cache files (CWE-59 / CWE-732).
    public func terminate() {
        lock.lock()
        defer { lock.unlock() }
        guard !isTerminated else { return }
        isTerminated = true
        try? FileManager.default.removeItem(at: sessionDirectoryURL)
    }

    /// Prepares a sandboxed cache directory with POSIX 0700 permissions.
    public static func prepareSandboxDirectory(sessionID: UUID) throws -> URL {
        let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let sessionDir = cachesURL
            .appendingPathComponent("SparkleSFTP", isDirectory: true)
            .appendingPathComponent("remote-edit", isDirectory: true)
            .appendingPathComponent(sessionID.uuidString, isDirectory: true)

        try FileManager.default.createDirectory(
            at: sessionDir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return sessionDir
    }
}
