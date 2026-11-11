import Foundation
import SparkleCore
import SparkleFileManager

public extension Notification.Name {
    static let sparkleConnectionsDidChange = Notification.Name("sparkleSFTP.connectionsDidChange")
    static let sparklePreferencesDidChange = Notification.Name("sparkleSFTP.preferencesDidChange")
    static let sparkleRequestNewFolder = Notification.Name("sparkleSFTP.requestNewFolder")
    static let sparklePaneFocusRequested = Notification.Name("sparkleSFTP.paneFocusRequested")
}

/// Workspace tab pairing an independent local directory view with an optional remote session and 1:1 shell state.
public struct WorkspaceTab: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var sessionID: UUID?
    public var title: String
    public var localPath: URL
    public var localHistory: PaneNavigationHistory
    public var localSortDescriptor: FileSortDescriptor
    public var isTerminalVisible: Bool

    public init(
        id: UUID = UUID(),
        sessionID: UUID? = nil,
        title: String,
        localPath: URL,
        localHistory: PaneNavigationHistory? = nil,
        localSortDescriptor: FileSortDescriptor = FileSortDescriptor(),
        isTerminalVisible: Bool = false
    ) {
        self.id = id
        self.sessionID = sessionID
        self.title = title
        self.localPath = localPath
        self.localHistory = localHistory ?? PaneNavigationHistory(initialPath: localPath.path)
        self.localSortDescriptor = localSortDescriptor
        self.isTerminalVisible = isTerminalVisible
    }
}

struct RemoteDirectoryPermissionTarget: Sendable {
    let path: RemotePath
    let mode: UInt32
    let profileID: UUID
}

struct LocalDirectoryPermissionTarget: Sendable {
    let url: URL
    let mode: UInt32
}

struct PendingFolderPermissionJob: Sendable {
    var remainingTaskIDs: Set<UUID>
    let remoteDirectories: [RemoteDirectoryPermissionTarget]
    let localDirectories: [LocalDirectoryPermissionTarget]
}

public struct CopyMoveRequest: Identifiable, Sendable {
    public let id = UUID()
    public let files: [RemoteFile]
    public let isLocal: Bool
    public let isMove: Bool
    public let defaultDestinationDir: String

    public init(files: [RemoteFile], isLocal: Bool, isMove: Bool, defaultDestinationDir: String) {
        self.files = files
        self.isLocal = isLocal
        self.isMove = isMove
        self.defaultDestinationDir = defaultDestinationDir
    }
}

public struct FileChecksumReport: Identifiable, Sendable {
    public let id = UUID()
    public let filename: String
    public let path: String
    public let isLocal: Bool
    public let sha256: String
    public let byteCount: Int64
    public let sourceNote: String
}

public struct FileComparisonReport: Identifiable, Sendable {
    public let id = UUID()
    public let filename: String
    public let localItem: RemoteFile?
    public let remoteItem: RemoteFile?
    public let localSHA256: String?
    public let remoteSHA256: String?
    public let verdictKey: String
}

public struct CustomCommandRequest: Identifiable, Sendable {
    public let id = UUID()
    public let targetFile: RemoteFile?
    public let currentRemoteDir: String
}

public struct CustomCommandResult: Sendable {
    public let command: String
    public let exitCode: Int
    public let stdout: String
    public let stderr: String
}
