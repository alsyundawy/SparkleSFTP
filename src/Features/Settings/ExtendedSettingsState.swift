import Foundation

/// Holds persistent configuration for extended v0.6.0 subsystems.
public struct ExtendedSettingsState: Equatable, Sendable {
    public var terminalFontName: String = "SF Mono"
    public var terminalFontSize: Double = 13.0
    public var terminalScrollbackLines: Int = 10000
    public var terminalBellMode: String = "audible"
    public var terminalOsc7SyncEnabled: Bool = true
    public var terminalOsc52Policy: String = "off"
    public var terminalLocalShellPath: String = "/bin/zsh"

    public var editorExternalAppPath: String = ""
    public var editorAutoUploadOnSave: Bool = false
    public var editorRemoteChangeDetection: Bool = true
    public var editorTabWidth: Int = 4
    public var editorAutoSave: Bool = false

    public var securityTouchIDInterval: String = "everyTime"
    public var securityClearKeychainCacheOnQuit: Bool = false
    public var securityAutoClearClipboardSeconds: Int = 30
    public var securityPrivacyRedactionEnabled: Bool = false
    public var securityActivityLogRetentionDays: Int = 7

    public var networkKeepAliveSeconds: Int = 15
    public var networkConnectTimeout: Int = 15
    public var networkIpv6Preferred: Bool = false
    public var networkSshAgentEnabled: Bool = false
    public var networkSftpSubsystemPath: String = "/usr/libexec/sftp-server"

    public var syncDefaultMode: String = "sizeAndMtime"
    public var syncDefaultExclusions: String = ".DS_Store,._*"
    public var syncWatchEnabled: Bool = false
    public var syncWatchDeleteMode: String = "off"
    public var bookmarksHistorySize: Int = 20
    public var bookmarksSyncBrowsingDefault: Bool = false

    public var transferSpeedLimitUpKBps: Int = 0
    public var transferSpeedLimitDownKBps: Int = 0
    public var transferAutoPipeline: Bool = false
    public var transferRetryCount: Int = 0
    public var transferRetryBackoffBase: Double = 1.0
    public var transferPreserveTimestamps: Bool = true
    public var transferUseFilepart: Bool = true
    public var transferVerifySHA256After: Bool = false
    public var transferRsyncPath: String = ""

    public var archiveDefaultFormat: String = "ZIP"
    public var archiveCompressionLevel: Int = 6

    public var workspaceRestoreOnLaunch: Bool = false
    public var isDirectoryComparisonActive: Bool = false
    public var directoryComparisonSyncBrowsing: Bool = false

    public init() {}
}
