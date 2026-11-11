import Foundation
import SparkleCore

public enum FileSortField: String, Sendable, CaseIterable {
    case name
    case size
    case modifiedDate
    case permissions
}

public struct FileSortDescriptor: Sendable, Equatable {
    public var field: FileSortField
    public var ascending: Bool
    public var foldersFirst: Bool

    public init(field: FileSortField = .name, ascending: Bool = true, foldersFirst: Bool = true) {
        self.field = field
        self.ascending = ascending
        self.foldersFirst = foldersFirst
    }

    /// Background-safe deterministic sorting supporting 100K+ directory entries (PERF-003).
    public static func sortRemoteFiles(_ files: [RemoteFile], by descriptor: FileSortDescriptor) async -> [RemoteFile] {
        await Task.detached(priority: .userInitiated) {
            files.sorted { lhs, rhs in
                if descriptor.foldersFirst, lhs.isDirectory != rhs.isDirectory {
                    return lhs.isDirectory && !rhs.isDirectory
                }

                let ordered: Bool
                switch descriptor.field {
                case .name:
                    let cmp = lhs.name.localizedStandardCompare(rhs.name)
                    ordered = descriptor.ascending ? (cmp == .orderedAscending) : (cmp == .orderedDescending)
                case .size:
                    if lhs.size == rhs.size {
                        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                    }
                    ordered = descriptor.ascending ? (lhs.size < rhs.size) : (lhs.size > rhs.size)
                case .modifiedDate:
                    let lDate = lhs.modificationTime ?? .distantPast
                    let rDate = rhs.modificationTime ?? .distantPast
                    if lDate == rDate {
                        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                    }
                    ordered = descriptor.ascending ? (lDate < rDate) : (lDate > rDate)
                case .permissions:
                    if lhs.permissions == rhs.permissions {
                        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                    }
                    ordered = descriptor.ascending
                        ? (lhs.permissions < rhs.permissions)
                        : (lhs.permissions > rhs.permissions)
                }
                return ordered
            }
        }.value
    }
}
