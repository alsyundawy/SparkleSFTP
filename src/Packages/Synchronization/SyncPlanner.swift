import Crypto
import Foundation
import SparkleCore
import SparkleTransferEngine

public enum SyncComparisonMode: String, Sendable, CaseIterable {
    case sizeAndMtime
    case sizeOnly
    case sha256Strict
}

public enum SyncDirection: String, Sendable, CaseIterable, Identifiable {
    case localToRemote
    case remoteToLocal
    case bidirectional

    public var id: String {
        rawValue
    }
}

public enum SyncActionDirection: String, Sendable, Equatable {
    case upload
    case download
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
    public let transferDirection: SyncActionDirection
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
        transferDirection: SyncActionDirection = .upload,
        isDirectory: Bool,
        size: Int64,
        expectedMtime: Date? = nil
    ) {
        self.id = id
        self.relativePath = relativePath
        self.kind = kind
        self.transferDirection = transferDirection
        self.isDirectory = isDirectory
        self.size = size
        self.expectedMtime = expectedMtime
    }
}

/// Immutable synchronization plan carrying a strict 60-second staleness expiry (LOG-003).
public struct SyncPlan: Sendable, Equatable {
    public let createdAt: Date
    public let expiresAt: Date
    public let direction: SyncDirection
    public let deleteExtras: Bool
    public let actions: [SyncAction]

    public init(
        createdAt: Date = Date(),
        expiresAt: Date? = nil,
        direction: SyncDirection = .localToRemote,
        deleteExtras: Bool = false,
        actions: [SyncAction]
    ) {
        self.createdAt = createdAt
        self.expiresAt = expiresAt ?? createdAt.addingTimeInterval(60)
        self.direction = direction
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

/// Pure non-mutating comparison and sync planner supporting Local->Remote, Remote->Local,
/// and Bidirectional merge sync (SCALE-003, LOG-003, TASK-108).
public enum SyncPlanner {
    public static func buildPlan(
        source: [ScannedFileEntry],
        destination: [ScannedFileEntry],
        direction: SyncDirection = .localToRemote,
        mode: SyncComparisonMode = .sizeAndMtime,
        deleteExtras: Bool = false,
        ttlSeconds: TimeInterval = 60,
        now: Date = Date()
    ) -> SyncPlan {
        let actions: [SyncAction] = switch direction {
        case .localToRemote:
            planOneWay(
                origin: source,
                target: destination,
                transferDirection: .upload,
                mode: mode,
                deleteExtras: deleteExtras
            )
        case .remoteToLocal:
            planOneWay(
                origin: destination,
                target: source,
                transferDirection: .download,
                mode: mode,
                deleteExtras: deleteExtras
            )
        case .bidirectional:
            planBidirectional(local: source, remote: destination, mode: mode)
        }

        return SyncPlan(
            createdAt: now,
            expiresAt: now.addingTimeInterval(ttlSeconds),
            direction: direction,
            deleteExtras: direction == .bidirectional ? false : deleteExtras,
            actions: actions
        )
    }

    private static func planOneWay(
        origin: [ScannedFileEntry],
        target: [ScannedFileEntry],
        transferDirection: SyncActionDirection,
        mode: SyncComparisonMode,
        deleteExtras: Bool
    ) -> [SyncAction] {
        let targetMap = Dictionary(uniqueKeysWithValues: target.map { ($0.relativePath, $0) })
        let originSet = Set(origin.map(\.relativePath))
        var actions: [SyncAction] = []

        for item in origin {
            guard let existing = targetMap[item.relativePath] else {
                actions.append(
                    SyncAction(
                        relativePath: item.relativePath,
                        kind: .create,
                        transferDirection: transferDirection,
                        isDirectory: item.isDirectory,
                        size: item.size,
                        expectedMtime: item.modificationTime
                    )
                )
                continue
            }
            if !item.isDirectory, filesDiffer(lhs: item, rhs: existing, mode: mode) {
                actions.append(
                    SyncAction(
                        relativePath: item.relativePath,
                        kind: .update,
                        transferDirection: transferDirection,
                        isDirectory: false,
                        size: item.size,
                        expectedMtime: existing.modificationTime
                    )
                )
            }
        }

        if deleteExtras {
            let extras = target
                .filter { !originSet.contains($0.relativePath) }
                .sorted { $0.relativePath.count > $1.relativePath.count }
            for extra in extras {
                actions.append(
                    SyncAction(
                        relativePath: extra.relativePath,
                        kind: .delete,
                        transferDirection: transferDirection,
                        isDirectory: extra.isDirectory,
                        size: extra.size,
                        expectedMtime: extra.modificationTime
                    )
                )
            }
        }
        return actions
    }

    private static func planBidirectional(
        local: [ScannedFileEntry],
        remote: [ScannedFileEntry],
        mode: SyncComparisonMode
    ) -> [SyncAction] {
        let remoteMap = Dictionary(uniqueKeysWithValues: remote.map { ($0.relativePath, $0) })
        let localMap = Dictionary(uniqueKeysWithValues: local.map { ($0.relativePath, $0) })
        var actions: [SyncAction] = []

        for localItem in local {
            guard let remoteItem = remoteMap[localItem.relativePath] else {
                actions.append(
                    SyncAction(
                        relativePath: localItem.relativePath,
                        kind: .create,
                        transferDirection: .upload,
                        isDirectory: localItem.isDirectory,
                        size: localItem.size,
                        expectedMtime: localItem.modificationTime
                    )
                )
                continue
            }
            guard !localItem.isDirectory, filesDiffer(lhs: localItem, rhs: remoteItem, mode: mode) else { continue }
            actions.append(bidirectionalDiffAction(localItem: localItem, remoteItem: remoteItem))
        }

        for remoteItem in remote where localMap[remoteItem.relativePath] == nil {
            actions.append(
                SyncAction(
                    relativePath: remoteItem.relativePath,
                    kind: .create,
                    transferDirection: .download,
                    isDirectory: remoteItem.isDirectory,
                    size: remoteItem.size,
                    expectedMtime: remoteItem.modificationTime
                )
            )
        }
        return actions
    }

    private static func bidirectionalDiffAction(
        localItem: ScannedFileEntry,
        remoteItem: ScannedFileEntry
    ) -> SyncAction {
        if let rTime = remoteItem.modificationTime,
           let lTime = localItem.modificationTime,
           rTime.timeIntervalSince(lTime) > 2.0 {
            return SyncAction(
                relativePath: remoteItem.relativePath,
                kind: .update,
                transferDirection: .download,
                isDirectory: false,
                size: remoteItem.size,
                expectedMtime: remoteItem.modificationTime
            )
        }
        return SyncAction(
            relativePath: localItem.relativePath,
            kind: .update,
            transferDirection: .upload,
            isDirectory: false,
            size: localItem.size,
            expectedMtime: remoteItem.modificationTime
        )
    }

    private static func filesDiffer(
        lhs: ScannedFileEntry,
        rhs: ScannedFileEntry,
        mode: SyncComparisonMode
    ) -> Bool {
        if lhs.size != rhs.size {
            return true
        }
        switch mode {
        case .sizeOnly:
            return false
        case .sizeAndMtime:
            guard let sTime = lhs.modificationTime, let tTime = rhs.modificationTime else {
                return true
            }
            return abs(sTime.timeIntervalSince(tTime)) > 2.0
        case .sha256Strict:
            if let sHash = lhs.sha256, let tHash = rhs.sha256 {
                return sHash != tHash
            }
            return true
        }
    }
}
