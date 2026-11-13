import Foundation

/// Detected native/third-party library, SSH/TLS runtime, shell, or external terminal integration.
public struct ToolchainLibraryStatus: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let category: String
    public let version: String
    public let isAvailable: Bool
    public let role: String
    public let detail: String

    public init(
        id: String,
        name: String,
        category: String,
        version: String,
        isAvailable: Bool,
        role: String,
        detail: String
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.version = version
        self.isAvailable = isAvailable
        self.role = role
        self.detail = detail
    }
}

/// Supported terminal options for opening interactive OpenSSH sessions cleanly.
public enum ExternalTerminalApp: String, Sendable, Codable, CaseIterable {
    case internalTerminal = "internal"
    case auto
    case iTerm2
    case appleTerminal

    public var displayName: String {
        switch self {
        case .internalTerminal: return "SparkleSFTP Internal Terminal (iTerm2-Style)"
        case .auto: return "Auto (Prefer iTerm2)"
        case .iTerm2: return "iTerm2"
        case .appleTerminal: return "Terminal.app"
        }
    }
}

/// Snapshot of runtime shells and external terminal tools available on the host macOS machine.
public struct HostToolchainReport: Sendable, Equatable {
    public let libraries: [ToolchainLibraryStatus]
    public let availableShells: [String]
    public let iTermAppURL: URL?
    public let appleTerminalURL: URL?
    public let openSSHBinaryURL: URL?
    public let openSSLBinaryURL: URL?

    public init(
        libraries: [ToolchainLibraryStatus] = [],
        availableShells: [String] = [],
        iTermAppURL: URL? = nil,
        appleTerminalURL: URL? = nil,
        openSSHBinaryURL: URL? = nil,
        openSSLBinaryURL: URL? = nil
    ) {
        self.libraries = libraries
        self.availableShells = availableShells
        self.iTermAppURL = iTermAppURL
        self.appleTerminalURL = appleTerminalURL
        self.openSSHBinaryURL = openSSHBinaryURL
        self.openSSLBinaryURL = openSSLBinaryURL
    }
}
