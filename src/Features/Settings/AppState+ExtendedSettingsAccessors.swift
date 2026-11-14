import Foundation

public extension AppState {
    var terminalFontName: String {
        get { extendedSettings.terminalFontName }
        set { extendedSettings.terminalFontName = newValue }
    }

    var terminalFontSize: Double {
        get { extendedSettings.terminalFontSize }
        set { extendedSettings.terminalFontSize = newValue }
    }

    var terminalScrollbackLines: Int {
        get { extendedSettings.terminalScrollbackLines }
        set { extendedSettings.terminalScrollbackLines = newValue }
    }

    var terminalBellMode: String {
        get { extendedSettings.terminalBellMode }
        set { extendedSettings.terminalBellMode = newValue }
    }

    var terminalOsc7SyncEnabled: Bool {
        get { extendedSettings.terminalOsc7SyncEnabled }
        set { extendedSettings.terminalOsc7SyncEnabled = newValue }
    }

    var terminalOsc52Policy: String {
        get { extendedSettings.terminalOsc52Policy }
        set { extendedSettings.terminalOsc52Policy = newValue }
    }

    var terminalLocalShellPath: String {
        get { extendedSettings.terminalLocalShellPath }
        set { extendedSettings.terminalLocalShellPath = newValue }
    }

    var editorExternalAppPath: String {
        get { extendedSettings.editorExternalAppPath }
        set { extendedSettings.editorExternalAppPath = newValue }
    }

    var editorAutoUploadOnSave: Bool {
        get { extendedSettings.editorAutoUploadOnSave }
        set { extendedSettings.editorAutoUploadOnSave = newValue }
    }

    var editorRemoteChangeDetection: Bool {
        get { extendedSettings.editorRemoteChangeDetection }
        set { extendedSettings.editorRemoteChangeDetection = newValue }
    }

    var editorTabWidth: Int {
        get { extendedSettings.editorTabWidth }
        set { extendedSettings.editorTabWidth = newValue }
    }

    var editorAutoSave: Bool {
        get { extendedSettings.editorAutoSave }
        set { extendedSettings.editorAutoSave = newValue }
    }

    var securityTouchIDInterval: String {
        get { extendedSettings.securityTouchIDInterval }
        set { extendedSettings.securityTouchIDInterval = newValue }
    }

    var securityClearKeychainCacheOnQuit: Bool {
        get { extendedSettings.securityClearKeychainCacheOnQuit }
        set { extendedSettings.securityClearKeychainCacheOnQuit = newValue }
    }

    var securityAutoClearClipboardSeconds: Int {
        get { extendedSettings.securityAutoClearClipboardSeconds }
        set { extendedSettings.securityAutoClearClipboardSeconds = newValue }
    }

    var securityPrivacyRedactionEnabled: Bool {
        get { extendedSettings.securityPrivacyRedactionEnabled }
        set { extendedSettings.securityPrivacyRedactionEnabled = newValue }
    }

    var securityActivityLogRetentionDays: Int {
        get { extendedSettings.securityActivityLogRetentionDays }
        set { extendedSettings.securityActivityLogRetentionDays = newValue }
    }

    var networkKeepAliveSeconds: Int {
        get { extendedSettings.networkKeepAliveSeconds }
        set { extendedSettings.networkKeepAliveSeconds = newValue }
    }

    var networkConnectTimeout: Int {
        get { extendedSettings.networkConnectTimeout }
        set { extendedSettings.networkConnectTimeout = newValue }
    }

    var networkIpv6Preferred: Bool {
        get { extendedSettings.networkIpv6Preferred }
        set { extendedSettings.networkIpv6Preferred = newValue }
    }

    var networkSshAgentEnabled: Bool {
        get { extendedSettings.networkSshAgentEnabled }
        set { extendedSettings.networkSshAgentEnabled = newValue }
    }

    var networkSftpSubsystemPath: String {
        get { extendedSettings.networkSftpSubsystemPath }
        set { extendedSettings.networkSftpSubsystemPath = newValue }
    }

    var syncDefaultMode: String {
        get { extendedSettings.syncDefaultMode }
        set { extendedSettings.syncDefaultMode = newValue }
    }

    var syncDefaultExclusions: String {
        get { extendedSettings.syncDefaultExclusions }
        set { extendedSettings.syncDefaultExclusions = newValue }
    }

    var syncWatchEnabled: Bool {
        get { extendedSettings.syncWatchEnabled }
        set { extendedSettings.syncWatchEnabled = newValue }
    }

    var syncWatchDeleteMode: String {
        get { extendedSettings.syncWatchDeleteMode }
        set { extendedSettings.syncWatchDeleteMode = newValue }
    }

    var bookmarksHistorySize: Int {
        get { extendedSettings.bookmarksHistorySize }
        set { extendedSettings.bookmarksHistorySize = newValue }
    }

    var bookmarksSyncBrowsingDefault: Bool {
        get { extendedSettings.bookmarksSyncBrowsingDefault }
        set { extendedSettings.bookmarksSyncBrowsingDefault = newValue }
    }

    var transferSpeedLimitUpKBps: Int {
        get { extendedSettings.transferSpeedLimitUpKBps }
        set { extendedSettings.transferSpeedLimitUpKBps = newValue }
    }

    var transferSpeedLimitDownKBps: Int {
        get { extendedSettings.transferSpeedLimitDownKBps }
        set { extendedSettings.transferSpeedLimitDownKBps = newValue }
    }

    var transferAutoPipeline: Bool {
        get { extendedSettings.transferAutoPipeline }
        set { extendedSettings.transferAutoPipeline = newValue }
    }

    var transferRetryCount: Int {
        get { extendedSettings.transferRetryCount }
        set { extendedSettings.transferRetryCount = newValue }
    }

    var transferRetryBackoffBase: Double {
        get { extendedSettings.transferRetryBackoffBase }
        set { extendedSettings.transferRetryBackoffBase = newValue }
    }

    var transferPreserveTimestamps: Bool {
        get { extendedSettings.transferPreserveTimestamps }
        set { extendedSettings.transferPreserveTimestamps = newValue }
    }

    var transferUseFilepart: Bool {
        get { extendedSettings.transferUseFilepart }
        set { extendedSettings.transferUseFilepart = newValue }
    }

    var transferVerifySHA256After: Bool {
        get { extendedSettings.transferVerifySHA256After }
        set { extendedSettings.transferVerifySHA256After = newValue }
    }

    var transferRsyncPath: String {
        get { extendedSettings.transferRsyncPath }
        set { extendedSettings.transferRsyncPath = newValue }
    }

    var archiveDefaultFormat: String {
        get { extendedSettings.archiveDefaultFormat }
        set { extendedSettings.archiveDefaultFormat = newValue }
    }

    var archiveCompressionLevel: Int {
        get { extendedSettings.archiveCompressionLevel }
        set { extendedSettings.archiveCompressionLevel = newValue }
    }

    var workspaceRestoreOnLaunch: Bool {
        get { extendedSettings.workspaceRestoreOnLaunch }
        set { extendedSettings.workspaceRestoreOnLaunch = newValue }
    }

    var isDirectoryComparisonActive: Bool {
        get { extendedSettings.isDirectoryComparisonActive }
        set { extendedSettings.isDirectoryComparisonActive = newValue }
    }

    var directoryComparisonSyncBrowsing: Bool {
        get { extendedSettings.directoryComparisonSyncBrowsing }
        set { extendedSettings.directoryComparisonSyncBrowsing = newValue }
    }
}
