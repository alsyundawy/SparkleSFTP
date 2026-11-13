import Foundation
import SparkleCore
import SparkleDesignSystem
import SwiftUI

// MARK: - Showcase Protocols & Status Types

public enum ShowcaseProtocolType: String, Sendable, CaseIterable, Identifiable {
    case sftp = "SFTP"
    case scp = "SCP"
    case ftps = "FTPS"
    case ftp = "FTP"

    public var id: String {
        rawValue
    }

    public var iconName: String {
        switch self {
        case .sftp: return "lock.shield.fill"
        case .scp: return "terminal.fill"
        case .ftps: return "lock.fill"
        case .ftp: return "exclamationmark.triangle.fill"
        }
    }

    public var badgeTint: Color {
        switch self {
        case .sftp: return Color.blue
        case .scp: return Color.indigo
        case .ftps: return Color.teal
        case .ftp: return Color.orange
        }
    }

    public var defaultPort: Int {
        switch self {
        case .sftp, .scp: return 22
        case .ftps: return 990
        case .ftp: return 21
        }
    }
}

public enum ShowcaseTransferStatus: String, Sendable, CaseIterable, Identifiable {
    case active = "Active"
    case queued = "Queued"
    case paused = "Paused"
    case completed = "Completed"
    case failed = "Failed"
    case conflict = "Conflict"

    public var id: String {
        rawValue
    }

    public var iconName: String {
        switch self {
        case .active: return "arrow.down.circle.fill"
        case .queued: return "clock.fill"
        case .paused: return "pause.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.octagon.fill"
        case .conflict: return "exclamationmark.2"
        }
    }

    public var badgeTint: Color {
        switch self {
        case .active: return Color.blue
        case .queued: return Color.gray
        case .paused: return Color.orange
        case .completed: return Color.green
        case .failed: return Color.red
        case .conflict: return Color.purple
        }
    }
}

public enum ShowcaseTransferDirection: String, Sendable {
    case upload = "Upload"
    case download = "Download"

    public var iconName: String {
        switch self {
        case .upload: return "arrow.up.circle.fill"
        case .download: return "arrow.down.circle.fill"
        }
    }
}

// MARK: - Core Showcase Data Models

public struct ShowcaseDiskSpace: Sendable, Equatable {
    public let totalBytes: Int64
    public let freeBytes: Int64
    public let mountPoint: String

    public init(totalBytes: Int64, freeBytes: Int64, mountPoint: String = "/") {
        self.totalBytes = totalBytes
        self.freeBytes = freeBytes
        self.mountPoint = mountPoint
    }

    public var usedBytes: Int64 {
        max(0, totalBytes - freeBytes)
    }

    public var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes)
    }

    public var freeFraction: Double {
        1.0 - usedFraction
    }

    public var formattedSummary: String {
        let freeStr = ByteCountFormatter.string(fromByteCount: freeBytes, countStyle: .file)
        let totalStr = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        return "\(freeStr) free of \(totalStr)"
    }
}

public struct ShowcaseFileItem: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let isDirectory: Bool
    public let isSymlink: Bool
    public let sizeBytes: Int64
    public let formattedSize: String
    public let permissions: String
    public let modifiedAt: String

    public init(
        name: String,
        isDirectory: Bool,
        isSymlink: Bool = false,
        sizeBytes: Int64 = 0,
        formattedSize: String = "-",
        permissions: String = "-rw-r--r--",
        modifiedAt: String = "2026-11-12 14:30"
    ) {
        id = name
        self.name = name
        self.isDirectory = isDirectory
        self.isSymlink = isSymlink
        self.sizeBytes = sizeBytes
        self.formattedSize = formattedSize
        self.permissions = permissions
        self.modifiedAt = modifiedAt
    }

    public var iconName: String {
        if isDirectory {
            return "folder.fill"
        } else if isSymlink {
            return "link"
        } else if name.hasSuffix(".swift") || name.hasSuffix(".c") || name.hasSuffix(".h") {
            return "curlybraces"
        } else if name.hasSuffix(".log") || name.hasSuffix(".txt") || name.hasSuffix(".md") {
            return "doc.text.fill"
        } else if name.hasSuffix(".gz") || name.hasSuffix(".tar") || name.hasSuffix(".zip") {
            return "archivebox.fill"
        } else if name.hasSuffix(".iso") || name.hasSuffix(".dmg") {
            return "opticaldiscdrive.fill"
        } else {
            return "doc.fill"
        }
    }

    public var iconTint: Color {
        if isDirectory {
            return Color.blue
        } else if isSymlink {
            return Color.cyan
        } else if name.hasSuffix(".log") {
            return Color.orange
        } else if name.hasSuffix(".gz") || name.hasSuffix(".tar") {
            return Color.purple
        } else {
            return Color.secondary
        }
    }
}

public struct ShowcaseTransferItem: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let filename: String
    public let sourcePath: String
    public let destinationPath: String
    public let direction: ShowcaseTransferDirection
    public let status: ShowcaseTransferStatus
    public let fraction: Double
    public let speedMBs: Double
    public let etaString: String
    public let totalSizeBytes: Int64

    public init(
        id: UUID = UUID(),
        filename: String,
        sourcePath: String,
        destinationPath: String,
        direction: ShowcaseTransferDirection,
        status: ShowcaseTransferStatus,
        fraction: Double,
        speedMBs: Double,
        etaString: String,
        totalSizeBytes: Int64
    ) {
        self.id = id
        self.filename = filename
        self.sourcePath = sourcePath
        self.destinationPath = destinationPath
        self.direction = direction
        self.status = status
        self.fraction = fraction
        self.speedMBs = speedMBs
        self.etaString = etaString
        self.totalSizeBytes = totalSizeBytes
    }

    public var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: totalSizeBytes, countStyle: .file)
    }

    public var formattedSpeed: String {
        String(format: "%.1f MB/s", speedMBs)
    }
}

public struct ShowcaseConnectionProfile: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let groupName: String
    public let protocolType: ShowcaseProtocolType
    public let host: String
    public let port: Int
    public let username: String
    public let keyPath: String?
    public let lastConnected: String
    public let isFavorite: Bool

    public init(
        id: String,
        name: String,
        groupName: String,
        protocolType: ShowcaseProtocolType,
        host: String,
        port: Int,
        username: String,
        keyPath: String? = nil,
        lastConnected: String = "Today at 10:14",
        isFavorite: Bool = false
    ) {
        self.id = id
        self.name = name
        self.groupName = groupName
        self.protocolType = protocolType
        self.host = host
        self.port = port
        self.username = username
        self.keyPath = keyPath
        self.lastConnected = lastConnected
        self.isFavorite = isFavorite
    }
}

public struct ShowcaseTerminalLine: Identifiable, Sendable, Equatable {
    public let id: Int
    public let prompt: String?
    public let command: String?
    public let output: String
    public let isError: Bool

    public init(id: Int, prompt: String? = nil, command: String? = nil, output: String, isError: Bool = false) {
        self.id = id
        self.prompt = prompt
        self.command = command
        self.output = output
        self.isError = isError
    }
}

// MARK: - Deterministic Showcase Datasets

public enum ShowcaseData {
    // MARK: - Partitions & Disks

    public static let remoteDiskSpace = ShowcaseDiskSpace(
        totalBytes: 120 * 1024 * 1024 * 1024,
        freeBytes: Int64(48.2 * 1024 * 1024 * 1024),
        mountPoint: "/var"
    )

    public static let localDiskSpace = ShowcaseDiskSpace(
        totalBytes: 1000 * 1024 * 1024 * 1024,
        freeBytes: 642 * 1024 * 1024 * 1024,
        mountPoint: "/System/Volumes/Data"
    )

    // MARK: - Saved Connection Profiles

    public static let showcaseProfiles: [ShowcaseConnectionProfile] = [
        ShowcaseConnectionProfile(
            id: "profile-1",
            name: "Production Web (EU-West)",
            groupName: "Production",
            protocolType: .sftp,
            host: "web-01.eu-west.internal",
            port: 22,
            username: "deploy",
            keyPath: "~/.ssh/id_ed25519_prod",
            lastConnected: "10 mins ago",
            isFavorite: true
        ),
        ShowcaseConnectionProfile(
            id: "profile-2",
            name: "Staging Cluster (US-East)",
            groupName: "Staging",
            protocolType: .sftp,
            host: "staging.us-east.internal",
            port: 2222,
            username: "admin",
            keyPath: "~/.ssh/id_rsa_staging",
            lastConnected: "Yesterday at 18:24",
            isFavorite: true
        ),
        ShowcaseConnectionProfile(
            id: "profile-3",
            name: "FreeBSD Ports Mirror",
            groupName: "Mirrors",
            protocolType: .scp,
            host: "ports.bsd-mirror.internal",
            port: 22,
            username: "freebsd",
            lastConnected: "3 days ago"
        ),
        ShowcaseConnectionProfile(
            id: "profile-4",
            name: "Cold Storage Archive NAS",
            groupName: "Storage",
            protocolType: .ftps,
            host: "nas-backup.internal",
            port: 990,
            username: "backup_agent",
            lastConnected: "1 week ago"
        ),
        ShowcaseConnectionProfile(
            id: "profile-5",
            name: "Legacy Testbed Insecure",
            groupName: "Legacy",
            protocolType: .ftp,
            host: "192.168.1.100",
            port: 21,
            username: "anonymous",
            lastConnected: "2 weeks ago"
        )
    ]

    public static var mockProfiles: [ShowcaseConnectionProfile] {
        showcaseProfiles
    }
}

// MARK: - Backward Compatibility Aliases

public typealias MockProtocolType = ShowcaseProtocolType
public typealias MockTransferStatus = ShowcaseTransferStatus
public typealias MockTransferDirection = ShowcaseTransferDirection
public typealias MockDiskSpace = ShowcaseDiskSpace
public typealias MockFileItem = ShowcaseFileItem
public typealias MockTransferItem = ShowcaseTransferItem
public typealias MockConnectionProfile = ShowcaseConnectionProfile
public typealias MockTerminalLine = ShowcaseTerminalLine
public typealias MockData = ShowcaseData
