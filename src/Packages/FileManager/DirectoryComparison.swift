import Foundation
import SparkleCore

/// Comparison criteria for evaluating dual-pane directory listings.
public enum ComparisonMode: String, Sendable, Codable, CaseIterable {
    case sizeAndMtime
    case sizeOnly
}

/// Comparison status of a file entry relative to the opposing pane.
public enum ComparisonDifference: String, Sendable, Equatable {
    case identical
    case onlyInLocal
    case onlyInRemote
    case differentSize
    case localNewer
    case remoteNewer
}

/// Aggregate output of a dual-pane directory comparison pass.
public struct DirectoryComparisonResult: Sendable, Equatable {
    public let localDifferences: [String: ComparisonDifference]
    public let remoteDifferences: [String: ComparisonDifference]
    public let localOnlyCount: Int
    public let remoteOnlyCount: Int
    public let differentCount: Int
    public let identicalCount: Int

    public init(
        localDifferences: [String: ComparisonDifference] = [:],
        remoteDifferences: [String: ComparisonDifference] = [:],
        localOnlyCount: Int = 0,
        remoteOnlyCount: Int = 0,
        differentCount: Int = 0,
        identicalCount: Int = 0
    ) {
        self.localDifferences = localDifferences
        self.remoteDifferences = remoteDifferences
        self.localOnlyCount = localOnlyCount
        self.remoteOnlyCount = remoteOnlyCount
        self.differentCount = differentCount
        self.identicalCount = identicalCount
    }
}

private struct LocalEvaluation {
    var diffs: [String: ComparisonDifference] = [:]
    var localOnlyCount = 0
    var differentCount = 0
    var identicalCount = 0
}

private struct RemoteEvaluation {
    var diffs: [String: ComparisonDifference] = [:]
    var remoteOnlyCount = 0
}

/// Pure, non-recursive directory comparison engine matching FileZilla & ForkLift specifications.
public enum DirectoryComparison {
    /// Compares two sets of file entries, evaluating missing files, size differences, and mtime offsets.
    public static func compare(
        localFiles: [RemoteFile],
        remoteFiles: [RemoteFile],
        mode: ComparisonMode = .sizeAndMtime,
        mtimeToleranceSeconds: TimeInterval = 2.0
    ) -> DirectoryComparisonResult {
        let remoteMap = buildFileMap(remoteFiles)
        let localMap = buildFileMap(localFiles)

        let localEval = evaluateLocalDifferences(
            localMap: localMap,
            remoteMap: remoteMap,
            mode: mode,
            tolerance: mtimeToleranceSeconds
        )

        let remoteEval = evaluateRemoteDifferences(
            remoteMap: remoteMap,
            localMap: localMap,
            localDiffs: localEval.diffs
        )

        return DirectoryComparisonResult(
            localDifferences: localEval.diffs,
            remoteDifferences: remoteEval.diffs,
            localOnlyCount: localEval.localOnlyCount,
            remoteOnlyCount: remoteEval.remoteOnlyCount,
            differentCount: localEval.differentCount,
            identicalCount: localEval.identicalCount
        )
    }

    private static func buildFileMap(_ files: [RemoteFile]) -> [String: RemoteFile] {
        var map: [String: RemoteFile] = [:]
        map.reserveCapacity(files.count)
        for file in files where file.name != "." && file.name != ".." {
            map[file.name] = file
        }
        return map
    }

    private static func evaluateLocalDifferences(
        localMap: [String: RemoteFile],
        remoteMap: [String: RemoteFile],
        mode: ComparisonMode,
        tolerance: TimeInterval
    ) -> LocalEvaluation {
        var eval = LocalEvaluation()
        eval.diffs.reserveCapacity(localMap.count)

        for (name, localFile) in localMap {
            guard let remoteFile = remoteMap[name] else {
                eval.diffs[name] = .onlyInLocal
                eval.localOnlyCount += 1
                continue
            }
            let diff = evaluateDifference(local: localFile, remote: remoteFile, mode: mode, tolerance: tolerance)
            eval.diffs[name] = diff
            if diff == .identical {
                eval.identicalCount += 1
            } else {
                eval.differentCount += 1
            }
        }
        return eval
    }

    private static func evaluateRemoteDifferences(
        remoteMap: [String: RemoteFile],
        localMap: [String: RemoteFile],
        localDiffs: [String: ComparisonDifference]
    ) -> RemoteEvaluation {
        var eval = RemoteEvaluation()
        eval.diffs.reserveCapacity(remoteMap.count)

        for (name, _) in remoteMap {
            if localMap[name] == nil {
                eval.diffs[name] = .onlyInRemote
                eval.remoteOnlyCount += 1
            } else if let localDiff = localDiffs[name] {
                eval.diffs[name] = invertDifference(localDiff)
            }
        }
        return eval
    }

    private static func invertDifference(_ diff: ComparisonDifference) -> ComparisonDifference {
        switch diff {
        case .localNewer: return .remoteNewer
        case .remoteNewer: return .localNewer
        default: return diff
        }
    }

    private static func evaluateDifference(
        local: RemoteFile,
        remote: RemoteFile,
        mode: ComparisonMode,
        tolerance: TimeInterval
    ) -> ComparisonDifference {
        if local.isDirectory != remote.isDirectory || (!local.isDirectory && local.size != remote.size) {
            return .differentSize
        }
        if mode == .sizeAndMtime,
           let localMtime = local.modificationTime,
           let remoteMtime = remote.modificationTime {
            let delta = localMtime.timeIntervalSince(remoteMtime)
            if abs(delta) > tolerance {
                return delta > 0 ? .localNewer : .remoteNewer
            }
        }
        return .identical
    }
}
