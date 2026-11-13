import Foundation

/// Defines supported remote operating system targets for command presets (v0.5.0).
public enum RemoteOSTarget: String, Sendable, Codable, CaseIterable {
    case linux = "Linux"
    case bsd = "BSD"
    case macOS
    case all = "Common"
}

/// A pre-configured or user-defined remote command preset (v0.5.0).
public struct RemoteCommandPreset: Identifiable, Sendable, Codable, Equatable {
    public let id: String
    public let name: String
    public let commandTemplate: String
    public let targetOS: RemoteOSTarget
    public let requiresSelection: Bool

    public init(
        id: String,
        name: String,
        commandTemplate: String,
        targetOS: RemoteOSTarget,
        requiresSelection: Bool = false
    ) {
        self.id = id
        self.name = name
        self.commandTemplate = commandTemplate
        self.targetOS = targetOS
        self.requiresSelection = requiresSelection
    }

    public static let defaultPresets: [RemoteCommandPreset] = [
        // Linux Presets
        RemoteCommandPreset(
            id: "linux-systemctl-status",
            name: "systemctl status !",
            commandTemplate: "systemctl status !",
            targetOS: .linux,
            requiresSelection: true
        ),
        RemoteCommandPreset(
            id: "linux-df-h",
            name: "df -h",
            commandTemplate: "df -h",
            targetOS: .linux
        ),
        RemoteCommandPreset(
            id: "linux-journalctl",
            name: "journalctl -u ! -n 50",
            commandTemplate: "journalctl -u ! -n 50",
            targetOS: .linux,
            requiresSelection: true
        ),
        RemoteCommandPreset(
            id: "linux-free-m",
            name: "free -m",
            commandTemplate: "free -m",
            targetOS: .linux
        ),
        RemoteCommandPreset(
            id: "linux-uptime",
            name: "uptime",
            commandTemplate: "uptime",
            targetOS: .linux
        ),

        // BSD Presets
        RemoteCommandPreset(
            id: "bsd-service-status",
            name: "service ! status",
            commandTemplate: "service ! status",
            targetOS: .bsd,
            requiresSelection: true
        ),
        RemoteCommandPreset(
            id: "bsd-top-1",
            name: "top -s 1",
            commandTemplate: "top -s 1",
            targetOS: .bsd
        ),
        RemoteCommandPreset(
            id: "bsd-sockstat",
            name: "sockstat -4",
            commandTemplate: "sockstat -4",
            targetOS: .bsd
        ),

        // macOS Presets
        RemoteCommandPreset(
            id: "macos-launchctl-list",
            name: "launchctl list",
            commandTemplate: "launchctl list",
            targetOS: .macOS
        ),
        RemoteCommandPreset(
            id: "macos-du-sh",
            name: "du -sh *",
            commandTemplate: "du -sh *",
            targetOS: .macOS
        ),
        RemoteCommandPreset(
            id: "macos-top-l1",
            name: "top -l 1",
            commandTemplate: "top -l 1",
            targetOS: .macOS
        ),
        RemoteCommandPreset(
            id: "macos-vmstat",
            name: "vm_stat",
            commandTemplate: "vm_stat",
            targetOS: .macOS
        ),

        // Common Presets
        RemoteCommandPreset(
            id: "common-pwd",
            name: "pwd",
            commandTemplate: "pwd",
            targetOS: .all
        ),
        RemoteCommandPreset(
            id: "common-ls-la",
            name: "ls -la !/",
            commandTemplate: "ls -la !/",
            targetOS: .all
        )
    ]
}
