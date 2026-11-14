import Foundation
import SparkleCore

public extension AppState {
    internal enum ExtendedPreferenceKey {
        static let terminalFontName = "sparklesftp.terminal.fontName"
        static let terminalFontSize = "sparklesftp.terminal.fontSize"
        static let terminalScrollback = "sparklesftp.terminal.scrollbackLines"
        static let terminalBellMode = "sparklesftp.terminal.bellMode"
        static let terminalOsc7Sync = "sparklesftp.terminal.osc7SyncEnabled"
        static let terminalOsc52Policy = "sparklesftp.terminal.osc52Policy"
        static let terminalShellPath = "sparklesftp.terminal.localShellPath"

        static let editorExternalApp = "sparklesftp.editor.externalAppPath"
        static let editorAutoUpload = "sparklesftp.editor.autoUploadOnSave"
        static let editorRemoteChange = "sparklesftp.editor.remoteChangeDetection"
        static let editorTabWidth = "sparklesftp.editor.tabWidth"
        static let editorAutoSave = "sparklesftp.editor.autoSave"

        static let securityTouchIDInterval = "sparklesftp.security.touchIDInterval"
        static let securityClearOnQuit = "sparklesftp.security.clearKeychainCacheOnQuit"
        static let securityClipboardTimeout = "sparklesftp.security.autoClearClipboardSeconds"
        static let securityPrivacyRedaction = "sparklesftp.security.privacyRedactionEnabled"
        static let securityLogRetention = "sparklesftp.security.activityLogRetentionDays"

        static let networkKeepAlive = "sparklesftp.network.keepAliveSeconds"
        static let networkTimeout = "sparklesftp.network.connectTimeout"
        static let networkIpv6 = "sparklesftp.network.ipv6Preferred"
        static let networkSshAgent = "sparklesftp.network.sshAgentEnabled"
        static let networkSubsystem = "sparklesftp.network.sftpSubsystemPath"

        static let syncMode = "sparklesftp.sync.defaultMode"
        static let syncExclusions = "sparklesftp.sync.defaultExclusions"
        static let syncWatchEnabled = "sparklesftp.sync.watchEnabled"
        static let syncWatchDelete = "sparklesftp.sync.watchDeleteMode"
        static let bookmarksHistorySize = "sparklesftp.bookmarks.historySize"
        static let bookmarksSyncBrowsing = "sparklesftp.bookmarks.syncBrowsingDefault"

        static let transferSpeedLimitUp = "sparklesftp.transfer.speedLimitUpKBps"
        static let transferSpeedLimitDown = "sparklesftp.transfer.speedLimitDownKBps"
        static let transferAutoPipeline = "sparklesftp.transfer.autoPipeline"
        static let transferRetryCount = "sparklesftp.transfer.retryCount"
        static let transferRetryBackoff = "sparklesftp.transfer.retryBackoffBase"
        static let transferPreserveTimestamps = "sparklesftp.transfer.preserveTimestamps"
        static let transferUseFilepart = "sparklesftp.transfer.useFilepart"
        static let transferVerifySHA256 = "sparklesftp.transfer.verifySHA256After"
        static let transferRsyncPath = "sparklesftp.transfer.rsyncPath"

        static let archiveFormat = "sparklesftp.archive.defaultFormat"
        static let archiveCompression = "sparklesftp.archive.compressionLevel"
        static let workspaceRestore = "sparklesftp.workspace.restoreOnLaunch"
    }

    internal func loadExtendedPreferences(_ defaults: UserDefaults) {
        loadTerminalPreferences(defaults)
        loadEditorPreferences(defaults)
        loadSecurityPreferences(defaults)
        loadNetworkPreferences(defaults)
        loadSyncPreferences(defaults)
        loadTransferExtendedPreferences(defaults)
        loadArchiveAndWorkspacePreferences(defaults)
    }

    private func loadTerminalPreferences(_ defaults: UserDefaults) {
        if let font = defaults.string(forKey: ExtendedPreferenceKey.terminalFontName), !font.isEmpty {
            terminalFontName = font
        }
        let size = defaults.double(forKey: ExtendedPreferenceKey.terminalFontSize)
        if size >= 9.0, size <= 36.0 {
            terminalFontSize = size
        }
        let scroll = defaults.integer(forKey: ExtendedPreferenceKey.terminalScrollback)
        if scroll >= 500 {
            terminalScrollbackLines = scroll
        }
        if let bell = defaults.string(forKey: ExtendedPreferenceKey.terminalBellMode) {
            terminalBellMode = bell
        }
        if defaults.object(forKey: ExtendedPreferenceKey.terminalOsc7Sync) != nil {
            terminalOsc7SyncEnabled = defaults.bool(forKey: ExtendedPreferenceKey.terminalOsc7Sync)
        }
        if let osc52 = defaults.string(forKey: ExtendedPreferenceKey.terminalOsc52Policy) {
            terminalOsc52Policy = osc52
        }
        if let shell = defaults.string(forKey: ExtendedPreferenceKey.terminalShellPath), !shell.isEmpty {
            terminalLocalShellPath = shell
        }
    }

    private func loadEditorPreferences(_ defaults: UserDefaults) {
        if let app = defaults.string(forKey: ExtendedPreferenceKey.editorExternalApp) {
            editorExternalAppPath = app
        }
        if defaults.object(forKey: ExtendedPreferenceKey.editorAutoUpload) != nil {
            editorAutoUploadOnSave = defaults.bool(forKey: ExtendedPreferenceKey.editorAutoUpload)
        }
        if defaults.object(forKey: ExtendedPreferenceKey.editorRemoteChange) != nil {
            editorRemoteChangeDetection = defaults.bool(forKey: ExtendedPreferenceKey.editorRemoteChange)
        }
        let tabW = defaults.integer(forKey: ExtendedPreferenceKey.editorTabWidth)
        if tabW >= 2, tabW <= 8 {
            editorTabWidth = tabW
        }
        if defaults.object(forKey: ExtendedPreferenceKey.editorAutoSave) != nil {
            editorAutoSave = defaults.bool(forKey: ExtendedPreferenceKey.editorAutoSave)
        }
    }

    private func loadSecurityPreferences(_ defaults: UserDefaults) {
        if let tid = defaults.string(forKey: ExtendedPreferenceKey.securityTouchIDInterval) {
            securityTouchIDInterval = tid
        }
        if defaults.object(forKey: ExtendedPreferenceKey.securityClearOnQuit) != nil {
            securityClearKeychainCacheOnQuit = defaults.bool(forKey: ExtendedPreferenceKey.securityClearOnQuit)
        }
        let clipSec = defaults.integer(forKey: ExtendedPreferenceKey.securityClipboardTimeout)
        if clipSec >= 5 {
            securityAutoClearClipboardSeconds = clipSec
        }
        if defaults.object(forKey: ExtendedPreferenceKey.securityPrivacyRedaction) != nil {
            securityPrivacyRedactionEnabled = defaults.bool(forKey: ExtendedPreferenceKey.securityPrivacyRedaction)
        }
        let retention = defaults.integer(forKey: ExtendedPreferenceKey.securityLogRetention)
        if retention >= 1 {
            securityActivityLogRetentionDays = retention
        }
    }

    private func loadNetworkPreferences(_ defaults: UserDefaults) {
        let keepAlive = defaults.integer(forKey: ExtendedPreferenceKey.networkKeepAlive)
        if keepAlive >= 0 {
            networkKeepAliveSeconds = keepAlive
        }
        let timeout = defaults.integer(forKey: ExtendedPreferenceKey.networkTimeout)
        if timeout >= 5 {
            networkConnectTimeout = timeout
        }
        if defaults.object(forKey: ExtendedPreferenceKey.networkIpv6) != nil {
            networkIpv6Preferred = defaults.bool(forKey: ExtendedPreferenceKey.networkIpv6)
        }
        if defaults.object(forKey: ExtendedPreferenceKey.networkSshAgent) != nil {
            networkSshAgentEnabled = defaults.bool(forKey: ExtendedPreferenceKey.networkSshAgent)
        }
        if let sub = defaults.string(forKey: ExtendedPreferenceKey.networkSubsystem), !sub.isEmpty {
            networkSftpSubsystemPath = sub
        }
    }

    private func loadSyncPreferences(_ defaults: UserDefaults) {
        if let mode = defaults.string(forKey: ExtendedPreferenceKey.syncMode) {
            syncDefaultMode = mode
        }
        if let excl = defaults.string(forKey: ExtendedPreferenceKey.syncExclusions) {
            syncDefaultExclusions = excl
        }
        if defaults.object(forKey: ExtendedPreferenceKey.syncWatchEnabled) != nil {
            syncWatchEnabled = defaults.bool(forKey: ExtendedPreferenceKey.syncWatchEnabled)
        }
        if let wDel = defaults.string(forKey: ExtendedPreferenceKey.syncWatchDelete) {
            syncWatchDeleteMode = wDel
        }
        let hist = defaults.integer(forKey: ExtendedPreferenceKey.bookmarksHistorySize)
        if hist >= 5 {
            bookmarksHistorySize = hist
        }
        if defaults.object(forKey: ExtendedPreferenceKey.bookmarksSyncBrowsing) != nil {
            bookmarksSyncBrowsingDefault = defaults.bool(forKey: ExtendedPreferenceKey.bookmarksSyncBrowsing)
        }
    }

    private func loadTransferExtendedPreferences(_ defaults: UserDefaults) {
        transferSpeedLimitUpKBps = defaults.integer(forKey: ExtendedPreferenceKey.transferSpeedLimitUp)
        transferSpeedLimitDownKBps = defaults.integer(forKey: ExtendedPreferenceKey.transferSpeedLimitDown)
        if defaults.object(forKey: ExtendedPreferenceKey.transferAutoPipeline) != nil {
            transferAutoPipeline = defaults.bool(forKey: ExtendedPreferenceKey.transferAutoPipeline)
        }
        transferRetryCount = defaults.integer(forKey: ExtendedPreferenceKey.transferRetryCount)
        let backoff = defaults.double(forKey: ExtendedPreferenceKey.transferRetryBackoff)
        if backoff >= 0.5 {
            transferRetryBackoffBase = backoff
        }
        if defaults.object(forKey: ExtendedPreferenceKey.transferPreserveTimestamps) != nil {
            transferPreserveTimestamps = defaults.bool(forKey: ExtendedPreferenceKey.transferPreserveTimestamps)
        }
        if defaults.object(forKey: ExtendedPreferenceKey.transferUseFilepart) != nil {
            transferUseFilepart = defaults.bool(forKey: ExtendedPreferenceKey.transferUseFilepart)
        }
        if defaults.object(forKey: ExtendedPreferenceKey.transferVerifySHA256) != nil {
            transferVerifySHA256After = defaults.bool(forKey: ExtendedPreferenceKey.transferVerifySHA256)
        }
        if let rsync = defaults.string(forKey: ExtendedPreferenceKey.transferRsyncPath) {
            transferRsyncPath = rsync
        }
    }

    private func loadArchiveAndWorkspacePreferences(_ defaults: UserDefaults) {
        if let fmt = defaults.string(forKey: ExtendedPreferenceKey.archiveFormat) {
            archiveDefaultFormat = fmt
        }
        let comp = defaults.integer(forKey: ExtendedPreferenceKey.archiveCompression)
        if comp >= 0, comp <= 9 {
            archiveCompressionLevel = comp
        }
        if defaults.object(forKey: ExtendedPreferenceKey.workspaceRestore) != nil {
            workspaceRestoreOnLaunch = defaults.bool(forKey: ExtendedPreferenceKey.workspaceRestore)
        }
    }

    internal func saveExtendedPreferences(_ defaults: UserDefaults) {
        saveTerminalPreferences(defaults)
        saveEditorPreferences(defaults)
        saveSecurityPreferences(defaults)
        saveNetworkAndSyncPreferences(defaults)
        saveTransferAndArchivePreferences(defaults)
    }

    private func saveTerminalPreferences(_ defaults: UserDefaults) {
        defaults.set(terminalFontName, forKey: ExtendedPreferenceKey.terminalFontName)
        defaults.set(terminalFontSize, forKey: ExtendedPreferenceKey.terminalFontSize)
        defaults.set(terminalScrollbackLines, forKey: ExtendedPreferenceKey.terminalScrollback)
        defaults.set(terminalBellMode, forKey: ExtendedPreferenceKey.terminalBellMode)
        defaults.set(terminalOsc7SyncEnabled, forKey: ExtendedPreferenceKey.terminalOsc7Sync)
        defaults.set(terminalOsc52Policy, forKey: ExtendedPreferenceKey.terminalOsc52Policy)
        defaults.set(terminalLocalShellPath, forKey: ExtendedPreferenceKey.terminalShellPath)
    }

    private func saveEditorPreferences(_ defaults: UserDefaults) {
        defaults.set(editorExternalAppPath, forKey: ExtendedPreferenceKey.editorExternalApp)
        defaults.set(editorAutoUploadOnSave, forKey: ExtendedPreferenceKey.editorAutoUpload)
        defaults.set(editorRemoteChangeDetection, forKey: ExtendedPreferenceKey.editorRemoteChange)
        defaults.set(editorTabWidth, forKey: ExtendedPreferenceKey.editorTabWidth)
        defaults.set(editorAutoSave, forKey: ExtendedPreferenceKey.editorAutoSave)
    }

    private func saveSecurityPreferences(_ defaults: UserDefaults) {
        defaults.set(securityTouchIDInterval, forKey: ExtendedPreferenceKey.securityTouchIDInterval)
        defaults.set(securityClearKeychainCacheOnQuit, forKey: ExtendedPreferenceKey.securityClearOnQuit)
        defaults.set(securityAutoClearClipboardSeconds, forKey: ExtendedPreferenceKey.securityClipboardTimeout)
        defaults.set(securityPrivacyRedactionEnabled, forKey: ExtendedPreferenceKey.securityPrivacyRedaction)
        defaults.set(securityActivityLogRetentionDays, forKey: ExtendedPreferenceKey.securityLogRetention)
    }

    private func saveNetworkAndSyncPreferences(_ defaults: UserDefaults) {
        defaults.set(networkKeepAliveSeconds, forKey: ExtendedPreferenceKey.networkKeepAlive)
        defaults.set(networkConnectTimeout, forKey: ExtendedPreferenceKey.networkTimeout)
        defaults.set(networkIpv6Preferred, forKey: ExtendedPreferenceKey.networkIpv6)
        defaults.set(networkSshAgentEnabled, forKey: ExtendedPreferenceKey.networkSshAgent)
        defaults.set(networkSftpSubsystemPath, forKey: ExtendedPreferenceKey.networkSubsystem)

        defaults.set(syncDefaultMode, forKey: ExtendedPreferenceKey.syncMode)
        defaults.set(syncDefaultExclusions, forKey: ExtendedPreferenceKey.syncExclusions)
        defaults.set(syncWatchEnabled, forKey: ExtendedPreferenceKey.syncWatchEnabled)
        defaults.set(syncWatchDeleteMode, forKey: ExtendedPreferenceKey.syncWatchDelete)
        defaults.set(bookmarksHistorySize, forKey: ExtendedPreferenceKey.bookmarksHistorySize)
        defaults.set(bookmarksSyncBrowsingDefault, forKey: ExtendedPreferenceKey.bookmarksSyncBrowsing)
    }

    private func saveTransferAndArchivePreferences(_ defaults: UserDefaults) {
        defaults.set(transferSpeedLimitUpKBps, forKey: ExtendedPreferenceKey.transferSpeedLimitUp)
        defaults.set(transferSpeedLimitDownKBps, forKey: ExtendedPreferenceKey.transferSpeedLimitDown)
        defaults.set(transferAutoPipeline, forKey: ExtendedPreferenceKey.transferAutoPipeline)
        defaults.set(transferRetryCount, forKey: ExtendedPreferenceKey.transferRetryCount)
        defaults.set(transferRetryBackoffBase, forKey: ExtendedPreferenceKey.transferRetryBackoff)
        defaults.set(transferPreserveTimestamps, forKey: ExtendedPreferenceKey.transferPreserveTimestamps)
        defaults.set(transferUseFilepart, forKey: ExtendedPreferenceKey.transferUseFilepart)
        defaults.set(transferVerifySHA256After, forKey: ExtendedPreferenceKey.transferVerifySHA256)
        defaults.set(transferRsyncPath, forKey: ExtendedPreferenceKey.transferRsyncPath)

        defaults.set(archiveDefaultFormat, forKey: ExtendedPreferenceKey.archiveFormat)
        defaults.set(archiveCompressionLevel, forKey: ExtendedPreferenceKey.archiveCompression)
        defaults.set(workspaceRestoreOnLaunch, forKey: ExtendedPreferenceKey.workspaceRestore)
    }
}
