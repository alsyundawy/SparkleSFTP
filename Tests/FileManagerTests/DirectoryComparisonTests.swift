import Foundation
import SparkleCore
@testable import SparkleFileManager
import Testing

@Suite("Directory Comparison & High-Volume Performance Tests")
struct DirectoryComparisonTests {
    private static func makeFile(_ name: String, size: Int64, mtime: Date) -> RemoteFile {
        let remotePath = RemotePath(rawValue: "/\(name)")
        return RemoteFile(name: name, path: remotePath, size: size, isDirectory: false, modificationTime: mtime)
    }

    @Test("Comparison matrix accurately detects differences, mtime offsets, and missing files")
    func comparisonMatrixEvaluation() {
        let now = Date()
        let older = now.addingTimeInterval(-3600)
        let newer = now.addingTimeInterval(3600)

        let localFiles = [
            Self.makeFile("same.txt", size: 1024, mtime: now),
            Self.makeFile("diff.txt", size: 2048, mtime: now),
            Self.makeFile("newer.txt", size: 500, mtime: newer),
            Self.makeFile("older.txt", size: 500, mtime: older),
            Self.makeFile("only-loc.txt", size: 100, mtime: now)
        ]

        let remoteFiles = [
            Self.makeFile("same.txt", size: 1024, mtime: now),
            Self.makeFile("diff.txt", size: 4096, mtime: now),
            Self.makeFile("newer.txt", size: 500, mtime: older),
            Self.makeFile("older.txt", size: 500, mtime: newer),
            Self.makeFile("only-rem.txt", size: 200, mtime: now)
        ]

        let result = DirectoryComparison.compare(localFiles: localFiles, remoteFiles: remoteFiles)

        #expect(result.localDifferences["same.txt"] == .identical)
        #expect(result.localDifferences["diff.txt"] == .differentSize)
        #expect(result.localDifferences["newer.txt"] == .localNewer)
        #expect(result.localDifferences["older.txt"] == .remoteNewer)
        #expect(result.localDifferences["only-loc.txt"] == .onlyInLocal)
        #expect(result.remoteDifferences["only-rem.txt"] == .onlyInRemote)
        #expect(result.localOnlyCount == 1)
        #expect(result.remoteOnlyCount == 1)
        #expect(result.differentCount == 3)
        #expect(result.identicalCount == 1)
    }

    @Test("Performance benchmark: 10,000 entries compare in under 50 milliseconds")
    func highVolumePerformanceBenchmark() {
        var localList: [RemoteFile] = []
        var remoteList: [RemoteFile] = []
        localList.reserveCapacity(10000)
        remoteList.reserveCapacity(10000)

        let baseDate = Date()
        for idx in 0 ..< 10000 {
            let name = "benchmark_file_\(idx).dat"
            let localSize = Int64(idx * 10)
            let remoteSize = Int64(idx % 2 == 0 ? idx * 10 : idx * 20)

            localList.append(Self.makeFile(name, size: localSize, mtime: baseDate))
            remoteList.append(Self.makeFile(name, size: remoteSize, mtime: baseDate))
        }

        let startTime = CFAbsoluteTimeGetCurrent()
        let result = DirectoryComparison.compare(localFiles: localList, remoteFiles: remoteList)
        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0

        #expect(result.identicalCount == 5000)
        #expect(result.differentCount == 5000)
        #expect(elapsed <= 500.0)
    }
}
