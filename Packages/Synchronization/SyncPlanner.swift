import Crypto
import Foundation
import SparkleCore
import SparkleTransferEngine

public enum SyncComparisonMode: String, Sendable, CaseIterable {
    case sizeAndMtime
    case sizeOnly
    case sha256Strict
}

public enum SyncActionKind: String, Sendable, Equatable {
    case create
    case update
    case delete
}

public struct SyncAction: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let relativePath: String
    public let kind: SyncActionKind
    public let isDirectory: Bool
    public let size: Int64
    public let expectedMtime: Date?

    public var isDestructive: Bool {
        kind == .delete || kind == .update
    }

    public init(
        id: UUID = UUID(),
        relativePath: String,
        kind: SyncActionKind,
        isDirectory: Bool,
        size: Int64,
        expectedMtime: Date? = nil
    ) {
        self.id = id
        self.relativePath = relativePath
        self.kind = kind
        self.isDirectory = isDirectory
        self.size = size
        self.expectedMtime = expectedMtime
    }
}

/// Immutable synchronization plan carrying a strict 60-second staleness expiry (LOG-003).
public struct SyncPlan: Sendable, Equatable {
    public let createdAt: Date
    public let expiresAt: Date
    public let deleteExtras: Bool
    public let actions: [SyncAction]

    public init(
        createdAt: Date = Date(),
        expiresAt: Date? = nil,
        deleteExtras: Bool = false,
        actions: [SyncAction]
    ) {
        self.createdAt = createdAt
        self.expiresAt = expiresAt ?? createdAt.addingTimeInterval(60)
        self.deleteExtras = deleteExtras
        self.actions = actions
    }

    public func isStale(at now: Date = Date()) -> Bool {
        now > expiresAt
    }

    public var createActions: [SyncAction] {
        actions.filter { $0.kind == .create }
    }

    public var updateActions: [SyncAction] {
        actions.filter { $0.kind == .update }
    }

    public var deleteActions: [SyncAction] {
        actions.filter { $0.kind == .delete }
    }
}

/// Pure non-mutating comparison and sync planner (SCALE-003, LOG-003).
public enum SyncPlanner {
    public static func buildPlan(
        source: [ScannedFileEntry],
        destination: [ScannedFileEntry],
        mode: SyncComparisonMode = .sizeAndMtime,
        deleteExtras: Bool = false,
        ttlSeconds: TimeInterval = 60,
        now: Date = Date()
    ) -> SyncPlan {
        let destMap = Dictionary(uniqueKeysWithValues: destination.map { ($0.relativePath, $0) })
        let sourceSet = Set(source.map(\.relativePath))
        var actions: [SyncAction] = []

        for item in source {
            guard let target = destMap[item.relativePath] else {
                actions.append(
                    SyncAction(
                        relativePath: item.relativePath,
                        kind: .create,
                        isDirectory: item.isDirectory,
                        size: item.size,
                        expectedMtime: item.modificationTime
                    )
                )
                continue
            }

            if !item.isDirectory, needsUpdate(source: item, target: target, mode: mode) {
                actions.append(
                    SyncAction(
                        relativePath: item.relativePath,
                        kind: .update,
                        isDirectory: false,
                        size: item.size,
                        expectedMtime: target.modificationTime
                    )
                )
            }
        }

        if deleteExtras {
            let extras = destination
                .filter { !sourceSet.contains($0.relativePath) }
                .sorted { $0.relativePath.count > $1.relativePath.count }
            for extra in extras {
                actions.append(
                    SyncAction(
                        relativePath: extra.relativePath,
                        kind: .delete,
                        isDirectory: extra.isDirectory,
                        size: extra.size,
                        expectedMtime: extra.modificationTime
                    )
                )
            }
        }

        return SyncPlan(
            createdAt: now,
            expiresAt: now.addingTimeInterval(ttlSeconds),
            deleteExtras: deleteExtras,
            actions: actions
        )
    }

    private static func needsUpdate(
        source: ScannedFileEntry,
        target: ScannedFileEntry,
        mode: SyncComparisonMode
    ) -> Bool {
        // Tier 1: size comparison (O(1))
        if source.size != target.size {
            return true
        }
        // Tier 2: mtime comparison
        switch mode {
        case .sizeOnly:
            return false
        case .sizeAndMtime:
            guard let sTime = source.modificationTime, let tTime = target.modificationTime else {
                return true
            }
            return sTime.timeIntervalSince(tTime) > 2.0
        case .sha256Strict:
            if let sHash = source.sha256, let tHash = target.sha256 {
                return sHash != tHash
            }
            guard let sTime = source.modificationTime, let tTime = target.modificationTime else {
                return true
            }
            return abs(sTime.timeIntervalSince(tTime)) > 1.0
        }
    }
}
