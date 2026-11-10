import Foundation
import SparkleCore

public enum ResumeDecision: Sendable, Equatable {
    case resume(fromOffset: Int64)
    case restart(reason: String)
}

/// Validates remote metadata + local partial file integrity before resuming interrupted transfers (LOG-002).
public enum ResumeValidator {
    public static func validateDownloadResume(
        remotePath: RemotePath,
        partialLocalURL: URL,
        checkpoint: TransferCheckpoint,
        remoteFS: any RemoteFileSystem
    ) async throws -> ResumeDecision {
        guard checkpoint.bytesTransferred > 0 else {
            return .restart(reason: "Zero checkpoint bytes")
        }

        let remoteMeta = try await remoteFS.metadata(at: remotePath)
        guard remoteMeta.size == checkpoint.remoteSize else {
            return .restart(reason: "Remote file size changed")
        }

        if let expectedMtime = checkpoint.remoteModificationTime,
           let actualMtime = remoteMeta.modificationTime,
           abs(expectedMtime.timeIntervalSince(actualMtime)) > 1.0 {
            return .restart(reason: "Remote modification timestamp changed")
        }

        guard FileManager.default.fileExists(atPath: partialLocalURL.path) else {
            return .restart(reason: "Local partial file missing")
        }

        let attrs = try FileManager.default.attributesOfItem(atPath: partialLocalURL.path)
        let localSize = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        guard localSize == checkpoint.bytesTransferred else {
            return .restart(
                reason: "Local partial byte count mismatch (\(localSize) != \(checkpoint.bytesTransferred))"
            )
        }

        return .resume(fromOffset: localSize)
    }
}
