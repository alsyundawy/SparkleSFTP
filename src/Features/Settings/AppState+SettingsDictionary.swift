import Foundation
import SparkleCore

public extension AppState {
    /// Resets all settings associated with a specific tab to their default values.
    func resetSettings(for tab: SettingsTabIdentifier) {
        let descriptors = SettingsRegistry.settings(for: tab)
        for descriptor in descriptors {
            applySettingValue(key: descriptor.key, value: descriptor.defaultValue)
        }
    }

    /// Resets all settings across all tabs to their default values.
    func resetAllSettingsToDefaults() {
        for descriptor in SettingsRegistry.allSettings {
            applySettingValue(key: descriptor.key, value: descriptor.defaultValue)
        }
    }

    /// Exports all non-secret preference keys into a serializable dictionary.
    func exportSettingsDictionary() -> [String: String] {
        var dict: [String: String] = [:]
        for descriptor in SettingsRegistry.allSettings {
            if let value = currentSettingValue(key: descriptor.key) {
                dict[descriptor.key] = value
            }
        }
        return dict
    }

    /// Imports setting values from a dictionary, safely validating and applying them.
    func importSettingsDictionary(_ dict: [String: String]) {
        for (key, value) in dict {
            applySettingValue(key: key, value: value)
        }
    }

    private func currentSettingValue(key: String) -> String? {
        Self.settingAccessors[key]?.get(self)
    }

    private func applySettingValue(key: String, value: String) {
        Self.settingAccessors[key]?.set(self, value)
    }
}

private struct SettingAccessor: Sendable {
    let get: @Sendable @MainActor (AppState) -> String?
    let set: @Sendable @MainActor (AppState, String) -> Void
}

@MainActor
extension AppState {
    private static let settingAccessors: [String: SettingAccessor] = {
        var map: [String: SettingAccessor] = [:]

        // General
        map["general.locale"] = SettingAccessor(
            get: { $0.activeLocaleCode },
            set: { $0.activeLocaleCode = $1 }
        )
        map["workspace.restoreOnLaunch"] = SettingAccessor(
            get: { String($0.workspaceRestoreOnLaunch) },
            set: { $0.workspaceRestoreOnLaunch = ($1 == "true") }
        )

        // Terminal
        map["terminal.fontName"] = SettingAccessor(
            get: { $0.terminalFontName },
            set: { $0.terminalFontName = $1 }
        )
        map["terminal.fontSize"] = SettingAccessor(
            get: { String($0.terminalFontSize) },
            set: {
                if let num = Double($1) {
                    $0.terminalFontSize = num
                }
            }
        )
        map["terminal.scrollbackLines"] = SettingAccessor(
            get: { String($0.terminalScrollbackLines) },
            set: {
                if let num = Int($1) {
                    $0.terminalScrollbackLines = num
                }
            }
        )
        map["terminal.bellMode"] = SettingAccessor(
            get: { $0.terminalBellMode },
            set: { $0.terminalBellMode = $1 }
        )
        map["terminal.osc7SyncEnabled"] = SettingAccessor(
            get: { String($0.terminalOsc7SyncEnabled) },
            set: { $0.terminalOsc7SyncEnabled = ($1 == "true") }
        )
        map["terminal.osc52Policy"] = SettingAccessor(
            get: { $0.terminalOsc52Policy },
            set: { $0.terminalOsc52Policy = $1 }
        )
        map["terminal.localShellPath"] = SettingAccessor(
            get: { $0.terminalLocalShellPath },
            set: { $0.terminalLocalShellPath = $1 }
        )

        // Editor
        map["editor.externalAppPath"] = SettingAccessor(
            get: { $0.editorExternalAppPath },
            set: { $0.editorExternalAppPath = $1 }
        )
        map["editor.autoUploadOnSave"] = SettingAccessor(
            get: { String($0.editorAutoUploadOnSave) },
            set: { $0.editorAutoUploadOnSave = ($1 == "true") }
        )
        map["editor.remoteChangeDetection"] = SettingAccessor(
            get: { String($0.editorRemoteChangeDetection) },
            set: { $0.editorRemoteChangeDetection = ($1 == "true") }
        )
        map["editor.tabWidth"] = SettingAccessor(
            get: { String($0.editorTabWidth) },
            set: {
                if let num = Int($1) {
                    $0.editorTabWidth = num
                }
            }
        )
        map["editor.autoSave"] = SettingAccessor(
            get: { String($0.editorAutoSave) },
            set: { $0.editorAutoSave = ($1 == "true") }
        )

        // Security
        map["security.touchIDInterval"] = SettingAccessor(
            get: { $0.securityTouchIDInterval },
            set: { $0.securityTouchIDInterval = $1 }
        )
        map["security.clearKeychainCacheOnQuit"] = SettingAccessor(
            get: { String($0.securityClearKeychainCacheOnQuit) },
            set: { $0.securityClearKeychainCacheOnQuit = ($1 == "true") }
        )
        map["security.autoClearClipboardSeconds"] = SettingAccessor(
            get: { String($0.securityAutoClearClipboardSeconds) },
            set: {
                if let num = Int($1) {
                    $0.securityAutoClearClipboardSeconds = num
                }
            }
        )
        map["security.privacyRedactionEnabled"] = SettingAccessor(
            get: { String($0.securityPrivacyRedactionEnabled) },
            set: { $0.securityPrivacyRedactionEnabled = ($1 == "true") }
        )
        map["security.activityLogRetentionDays"] = SettingAccessor(
            get: { String($0.securityActivityLogRetentionDays) },
            set: {
                if let num = Int($1) {
                    $0.securityActivityLogRetentionDays = num
                }
            }
        )

        // Network
        map["network.keepAliveSeconds"] = SettingAccessor(
            get: { String($0.networkKeepAliveSeconds) },
            set: {
                if let num = Int($1) {
                    $0.networkKeepAliveSeconds = num
                }
            }
        )
        map["network.connectTimeout"] = SettingAccessor(
            get: { String($0.networkConnectTimeout) },
            set: {
                if let num = Int($1) {
                    $0.networkConnectTimeout = num
                }
            }
        )
        map["network.ipv6Preferred"] = SettingAccessor(
            get: { String($0.networkIpv6Preferred) },
            set: { $0.networkIpv6Preferred = ($1 == "true") }
        )
        map["network.sshAgentEnabled"] = SettingAccessor(
            get: { String($0.networkSshAgentEnabled) },
            set: { $0.networkSshAgentEnabled = ($1 == "true") }
        )
        map["network.sftpSubsystemPath"] = SettingAccessor(
            get: { $0.networkSftpSubsystemPath },
            set: { $0.networkSftpSubsystemPath = $1 }
        )

        // Sync
        map["sync.defaultMode"] = SettingAccessor(
            get: { $0.syncDefaultMode },
            set: { $0.syncDefaultMode = $1 }
        )
        map["sync.defaultExclusions"] = SettingAccessor(
            get: { $0.syncDefaultExclusions },
            set: { $0.syncDefaultExclusions = $1 }
        )
        map["sync.watchEnabled"] = SettingAccessor(
            get: { String($0.syncWatchEnabled) },
            set: { $0.syncWatchEnabled = ($1 == "true") }
        )
        map["sync.watchDeleteMode"] = SettingAccessor(
            get: { $0.syncWatchDeleteMode },
            set: { $0.syncWatchDeleteMode = $1 }
        )
        map["bookmarks.historySize"] = SettingAccessor(
            get: { String($0.bookmarksHistorySize) },
            set: {
                if let num = Int($1) {
                    $0.bookmarksHistorySize = num
                }
            }
        )
        map["bookmarks.syncBrowsingDefault"] = SettingAccessor(
            get: { String($0.bookmarksSyncBrowsingDefault) },
            set: { $0.bookmarksSyncBrowsingDefault = ($1 == "true") }
        )

        // Transfers
        map["transfer.speedLimitUpKBps"] = SettingAccessor(
            get: { String($0.transferSpeedLimitUpKBps) },
            set: {
                if let num = Int($1) {
                    $0.transferSpeedLimitUpKBps = num
                }
            }
        )
        map["transfer.speedLimitDownKBps"] = SettingAccessor(
            get: { String($0.transferSpeedLimitDownKBps) },
            set: {
                if let num = Int($1) {
                    $0.transferSpeedLimitDownKBps = num
                }
            }
        )
        map["transfer.autoPipeline"] = SettingAccessor(
            get: { String($0.transferAutoPipeline) },
            set: { $0.transferAutoPipeline = ($1 == "true") }
        )
        map["transfer.retryCount"] = SettingAccessor(
            get: { String($0.transferRetryCount) },
            set: {
                if let num = Int($1) {
                    $0.transferRetryCount = num
                }
            }
        )
        map["transfer.retryBackoffBase"] = SettingAccessor(
            get: { String($0.transferRetryBackoffBase) },
            set: {
                if let num = Double($1) {
                    $0.transferRetryBackoffBase = num
                }
            }
        )
        map["transfer.preserveTimestamps"] = SettingAccessor(
            get: { String($0.transferPreserveTimestamps) },
            set: { $0.transferPreserveTimestamps = ($1 == "true") }
        )
        map["transfer.useFilepart"] = SettingAccessor(
            get: { String($0.transferUseFilepart) },
            set: { $0.transferUseFilepart = ($1 == "true") }
        )
        map["transfer.verifySHA256After"] = SettingAccessor(
            get: { String($0.transferVerifySHA256After) },
            set: { $0.transferVerifySHA256After = ($1 == "true") }
        )
        map["transfer.rsyncPath"] = SettingAccessor(
            get: { $0.transferRsyncPath },
            set: { $0.transferRsyncPath = $1 }
        )

        // Archives
        map["archive.defaultFormat"] = SettingAccessor(
            get: { $0.archiveDefaultFormat },
            set: { $0.archiveDefaultFormat = $1 }
        )
        map["archive.compressionLevel"] = SettingAccessor(
            get: { String($0.archiveCompressionLevel) },
            set: {
                if let num = Int($1) {
                    $0.archiveCompressionLevel = num
                }
            }
        )

        return map
    }()
}
