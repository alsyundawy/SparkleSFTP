import Foundation

/// Real-time progress payload emitted during remote file transfers.
public struct TransferProgress: Sendable, Equatable {
    public let bytesTransferred: Int64
    public let totalBytes: Int64
    public let bytesPerSecond: Int64

    public init(bytesTransferred: Int64, totalBytes: Int64, bytesPerSecond: Int64) {
        self.bytesTransferred = max(0, bytesTransferred)
        self.totalBytes = max(0, totalBytes)
        self.bytesPerSecond = max(0, bytesPerSecond)
    }

    public var percentage: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1.0, Double(bytesTransferred) / Double(totalBytes))
    }

    public var estimatedTimeRemaining: Duration? {
        guard bytesPerSecond > 0, totalBytes > bytesTransferred else { return nil }
        let remainingBytes = totalBytes - bytesTransferred
        return .seconds(remainingBytes / bytesPerSecond)
    }
}

public enum TransferDirection: String, Sendable, Codable {
    case upload
    case download
}

public enum TransferPriority: Int, Sendable, Codable, Comparable {
    case low = 0
    case normal = 1
    case high = 2

    public static func < (lhs: TransferPriority, rhs: TransferPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum TransferEndpoint: Sendable, Codable, Hashable {
    case local(url: URL)
    case remote(profileID: UUID, host: String, path: RemotePath)

    public var hostKey: String {
        switch self {
        case .local:
            return "localhost"
        case let .remote(_, host, _):
            return host
        }
    }

    public var displayPath: String {
        switch self {
        case let .local(url):
            return url.path
        case let .remote(_, host, path):
            return "\(host):\(path.rawValue)"
        }
    }
}

/// Static transfer descriptor separated from mutable progress state to prevent CoW overhead (BUG-003).
public struct TransferTaskMetadata: Identifiable, Sendable, Codable, Equatable {
    public let id: UUID
    public let direction: TransferDirection
    public let source: TransferEndpoint
    public let destination: TransferEndpoint
    public let totalBytes: Int64
    public let priority: TransferPriority
    public let expectedSHA256: String?
    public let conflictPolicyOverride: TransferConflictPolicy?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        direction: TransferDirection,
        source: TransferEndpoint,
        destination: TransferEndpoint,
        totalBytes: Int64,
        priority: TransferPriority = .normal,
        expectedSHA256: String? = nil,
        conflictPolicyOverride: TransferConflictPolicy? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.direction = direction
        self.source = source
        self.destination = destination
        self.totalBytes = max(0, totalBytes)
        self.priority = priority
        self.expectedSHA256 = expectedSHA256
        self.conflictPolicyOverride = conflictPolicyOverride
        self.createdAt = createdAt
    }

    public var targetHost: String {
        switch direction {
        case .upload:
            return destination.hostKey
        case .download:
            return source.hostKey
        }
    }
}

public enum TransferStatus: Sendable, Equatable {
    case queued
    case preparing
    case connecting
    case transferring(bytesPerSecond: Int64)
    case verifying
    case finalizing
    case completed
    case paused
    case interrupted
    case cancelled
    case failed(AppError)
    case needsReview

    public var statusCode: String {
        switch self {
        case .queued: return "queued"
        case .preparing: return "preparing"
        case .connecting: return "connecting"
        case .transferring: return "transferring"
        case .verifying: return "verifying"
        case .finalizing: return "finalizing"
        case .completed: return "completed"
        case .paused: return "paused"
        case .interrupted: return "interrupted"
        case .cancelled: return "cancelled"
        case .failed: return "failed"
        case .needsReview: return "needsReview"
        }
    }

    public var isTerminal: Bool {
        switch self {
        case .completed, .cancelled, .failed:
            return true
        default:
            return false
        }
    }

    public var isActive: Bool {
        switch self {
        case .preparing, .connecting, .transferring, .verifying, .finalizing:
            return true
        default:
            return false
        }
    }
}

public struct TransferCheckpoint: Sendable, Codable, Equatable {
    public let bytesTransferred: Int64
    public let remoteSize: Int64
    public let remoteModificationTime: Date?
    public let partialLocalPath: String?
    public let updatedAt: Date

    public init(
        bytesTransferred: Int64,
        remoteSize: Int64,
        remoteModificationTime: Date?,
        partialLocalPath: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.bytesTransferred = bytesTransferred
        self.remoteSize = remoteSize
        self.remoteModificationTime = remoteModificationTime
        self.partialLocalPath = partialLocalPath
        self.updatedAt = updatedAt
    }
}

public struct TransferSnapshot: Identifiable, Sendable, Equatable {
    public let metadata: TransferTaskMetadata
    public let status: TransferStatus
    public let progress: TransferProgress
    public let checkpoint: TransferCheckpoint?

    public var id: UUID {
        metadata.id
    }

    public init(
        metadata: TransferTaskMetadata,
        status: TransferStatus,
        progress: TransferProgress,
        checkpoint: TransferCheckpoint? = nil
    ) {
        self.metadata = metadata
        self.status = status
        self.progress = progress
        self.checkpoint = checkpoint
    }
}

public enum TransferConflictPolicy: String, Sendable, Codable, CaseIterable {
    case ask
    case skip
    case rename
    case overwrite
    case overwriteIfNewer
    case overwriteIfDifferentSize
    case overwriteIfDifferentSizeOrNewer
    case resume
}

public enum TransferConflictResolution: Sendable, Equatable {
    case skip
    case overwrite
    case resume
    case rename(newFilename: String)
}

public enum TransferConflictScope: String, Sendable, Codable, CaseIterable {
    case all
    case uploadsOnly
    case downloadsOnly
}

public struct TransferConflictDecision: Sendable, Equatable {
    public let resolution: TransferConflictResolution
    public let applyToQueue: Bool
    public let queuePolicy: TransferConflictPolicy?
    public let scope: TransferConflictScope

    public init(
        resolution: TransferConflictResolution,
        applyToQueue: Bool = false,
        queuePolicy: TransferConflictPolicy? = nil,
        scope: TransferConflictScope = .all
    ) {
        self.resolution = resolution
        self.applyToQueue = applyToQueue
        self.queuePolicy = queuePolicy
        self.scope = scope
    }
}

public enum DisconnectPolicy: Sendable, Equatable {
    case cancelAllTransfers
    case waitForCompletion
    case pauseAndDisconnect
}
