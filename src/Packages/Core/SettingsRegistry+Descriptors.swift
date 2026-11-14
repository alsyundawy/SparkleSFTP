import Foundation

public extension SettingsRegistry {
    static let allSettings: [SettingDescriptor] =
        generalAndTerminalSettings + editorAndSecuritySettings + networkAndSyncSettings + transferAndArchiveSettings

    static let generalAndTerminalSettings: [SettingDescriptor] = [
        SettingDescriptor(
            key: "general.locale",
            tab: .general,
            titleKey: "prefs.language",
            valueType: .string,
            defaultValue: "en"
        ),
        SettingDescriptor(
            key: "workspace.restoreOnLaunch",
            tab: .general,
            titleKey: "prefs.general.restoreWorkspace",
            valueType: .bool,
            defaultValue: "false"
        ),
        SettingDescriptor(
            key: "terminal.fontName",
            tab: .terminal,
            titleKey: "prefs.terminal.fontName",
            valueType: .string,
            defaultValue: "SF Mono"
        ),
        SettingDescriptor(
            key: "terminal.fontSize",
            tab: .terminal,
            titleKey: "prefs.terminal.fontSize",
            valueType: .double,
            defaultValue: "13.0",
            minValue: 9.0,
            maxValue: 36.0
        ),
        SettingDescriptor(
            key: "terminal.scrollbackLines",
            tab: .terminal,
            titleKey: "prefs.terminal.scrollback",
            valueType: .int,
            defaultValue: "10000",
            minValue: 500.0,
            maxValue: 100_000.0
        ),
        SettingDescriptor(
            key: "terminal.bellMode",
            tab: .terminal,
            titleKey: "prefs.terminal.bellMode",
            valueType: .enumChoice,
            defaultValue: "audible"
        ),
        SettingDescriptor(
            key: "terminal.osc7SyncEnabled",
            tab: .terminal,
            titleKey: "prefs.terminal.osc7Sync",
            valueType: .bool,
            defaultValue: "true"
        ),
        SettingDescriptor(
            key: "terminal.osc52Policy",
            tab: .terminal,
            titleKey: "prefs.terminal.osc52Policy",
            valueType: .enumChoice,
            defaultValue: "off"
        ),
        SettingDescriptor(
            key: "terminal.localShellPath",
            tab: .terminal,
            titleKey: "prefs.terminal.shellPath",
            valueType: .string,
            defaultValue: "/bin/zsh"
        )
    ]

    static let editorAndSecuritySettings: [SettingDescriptor] = [
        SettingDescriptor(
            key: "editor.externalAppPath",
            tab: .editor,
            titleKey: "prefs.editor.externalApp",
            valueType: .string,
            defaultValue: ""
        ),
        SettingDescriptor(
            key: "editor.autoUploadOnSave",
            tab: .editor,
            titleKey: "prefs.editor.autoUpload",
            valueType: .bool,
            defaultValue: "false"
        ),
        SettingDescriptor(
            key: "editor.remoteChangeDetection",
            tab: .editor,
            titleKey: "prefs.editor.remoteChange",
            valueType: .bool,
            defaultValue: "true"
        ),
        SettingDescriptor(
            key: "editor.tabWidth",
            tab: .editor,
            titleKey: "prefs.editor.tabWidth",
            valueType: .int,
            defaultValue: "4",
            minValue: 2.0,
            maxValue: 8.0
        ),
        SettingDescriptor(
            key: "editor.autoSave",
            tab: .editor,
            titleKey: "prefs.editor.autoSave",
            valueType: .bool,
            defaultValue: "false"
        ),
        SettingDescriptor(
            key: "security.touchIDInterval",
            tab: .security,
            titleKey: "prefs.security.touchIDInterval",
            valueType: .enumChoice,
            defaultValue: "everyTime"
        ),
        SettingDescriptor(
            key: "security.clearKeychainCacheOnQuit",
            tab: .security,
            titleKey: "prefs.security.clearOnQuit",
            valueType: .bool,
            defaultValue: "false"
        ),
        SettingDescriptor(
            key: "security.autoClearClipboardSeconds",
            tab: .security,
            titleKey: "prefs.security.clipboardTimeout",
            valueType: .int,
            defaultValue: "30",
            minValue: 5.0,
            maxValue: 300.0
        ),
        SettingDescriptor(
            key: "security.privacyRedactionEnabled",
            tab: .security,
            titleKey: "prefs.security.privacyRedaction",
            valueType: .bool,
            defaultValue: "false"
        ),
        SettingDescriptor(
            key: "security.activityLogRetentionDays",
            tab: .security,
            titleKey: "prefs.security.logRetention",
            valueType: .int,
            defaultValue: "7",
            minValue: 1.0,
            maxValue: 90.0
        )
    ]

    static let networkAndSyncSettings: [SettingDescriptor] = [
        SettingDescriptor(
            key: "network.keepAliveSeconds",
            tab: .network,
            titleKey: "prefs.network.keepAlive",
            valueType: .int,
            defaultValue: "15",
            minValue: 0.0,
            maxValue: 300.0
        ),
        SettingDescriptor(
            key: "network.connectTimeout",
            tab: .network,
            titleKey: "prefs.network.timeout",
            valueType: .int,
            defaultValue: "15",
            minValue: 5.0,
            maxValue: 120.0
        ),
        SettingDescriptor(
            key: "network.ipv6Preferred",
            tab: .network,
            titleKey: "prefs.network.ipv6",
            valueType: .bool,
            defaultValue: "false"
        ),
        SettingDescriptor(
            key: "network.sshAgentEnabled",
            tab: .network,
            titleKey: "prefs.network.sshAgent",
            valueType: .bool,
            defaultValue: "false"
        ),
        SettingDescriptor(
            key: "network.sftpSubsystemPath",
            tab: .network,
            titleKey: "prefs.network.subsystem",
            valueType: .string,
            defaultValue: "/usr/libexec/sftp-server"
        ),
        SettingDescriptor(
            key: "sync.defaultMode",
            tab: .sync,
            titleKey: "prefs.sync.mode",
            valueType: .enumChoice,
            defaultValue: "sizeAndMtime"
        ),
        SettingDescriptor(
            key: "sync.defaultExclusions",
            tab: .sync,
            titleKey: "prefs.sync.exclusions",
            valueType: .string,
            defaultValue: ".DS_Store,._*"
        ),
        SettingDescriptor(
            key: "sync.watchEnabled",
            tab: .sync,
            titleKey: "prefs.sync.watchEnabled",
            valueType: .bool,
            defaultValue: "false"
        ),
        SettingDescriptor(
            key: "sync.watchDeleteMode",
            tab: .sync,
            titleKey: "prefs.sync.watchDelete",
            valueType: .enumChoice,
            defaultValue: "off"
        ),
        SettingDescriptor(
            key: "bookmarks.historySize",
            tab: .sync,
            titleKey: "prefs.sync.historySize",
            valueType: .int,
            defaultValue: "20",
            minValue: 5.0,
            maxValue: 100.0
        ),
        SettingDescriptor(
            key: "bookmarks.syncBrowsingDefault",
            tab: .sync,
            titleKey: "prefs.sync.syncBrowsing",
            valueType: .bool,
            defaultValue: "false"
        )
    ]

    static let transferAndArchiveSettings: [SettingDescriptor] = [
        SettingDescriptor(
            key: "transfer.speedLimitUpKBps",
            tab: .transfers,
            titleKey: "prefs.transfers.speedLimitUp",
            valueType: .int,
            defaultValue: "0",
            minValue: 0.0,
            maxValue: 100_000.0
        ),
        SettingDescriptor(
            key: "transfer.speedLimitDownKBps",
            tab: .transfers,
            titleKey: "prefs.transfers.speedLimitDown",
            valueType: .int,
            defaultValue: "0",
            minValue: 0.0,
            maxValue: 100_000.0
        ),
        SettingDescriptor(
            key: "transfer.autoPipeline",
            tab: .transfers,
            titleKey: "prefs.transfers.autoPipeline",
            valueType: .bool,
            defaultValue: "false"
        ),
        SettingDescriptor(
            key: "transfer.retryCount",
            tab: .transfers,
            titleKey: "prefs.transfers.retryCount",
            valueType: .int,
            defaultValue: "0",
            minValue: 0.0,
            maxValue: 5.0
        ),
        SettingDescriptor(
            key: "transfer.retryBackoffBase",
            tab: .transfers,
            titleKey: "prefs.transfers.retryBackoff",
            valueType: .double,
            defaultValue: "1.0",
            minValue: 0.5,
            maxValue: 10.0
        ),
        SettingDescriptor(
            key: "transfer.preserveTimestamps",
            tab: .transfers,
            titleKey: "prefs.transfers.preserveTimestamps",
            valueType: .bool,
            defaultValue: "true"
        ),
        SettingDescriptor(
            key: "transfer.useFilepart",
            tab: .transfers,
            titleKey: "prefs.transfers.useFilepart",
            valueType: .bool,
            defaultValue: "true"
        ),
        SettingDescriptor(
            key: "transfer.verifySHA256After",
            tab: .transfers,
            titleKey: "prefs.transfers.verifySHA256",
            valueType: .bool,
            defaultValue: "false"
        ),
        SettingDescriptor(
            key: "transfer.rsyncPath",
            tab: .transfers,
            titleKey: "prefs.transfers.rsyncPath",
            valueType: .string,
            defaultValue: ""
        ),
        SettingDescriptor(
            key: "archive.defaultFormat",
            tab: .archives,
            titleKey: "prefs.archives.defaultFormat",
            valueType: .enumChoice,
            defaultValue: "ZIP"
        ),
        SettingDescriptor(
            key: "archive.compressionLevel",
            tab: .archives,
            titleKey: "prefs.archives.compressionLevel",
            valueType: .int,
            defaultValue: "6",
            minValue: 0.0,
            maxValue: 9.0
        )
    ]
}
