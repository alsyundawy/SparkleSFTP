import Foundation

/// Release channel preference for update checks.
public enum AutoUpdateChannel: String, Sendable, Codable, CaseIterable, Identifiable {
    case stable
    case beta

    public var id: String {
        rawValue
    }
}

/// Update polling frequency options stored in user preferences.
public enum UpdateCheckFrequency: Int, Sendable, Codable, CaseIterable, Identifiable {
    case hourly = 1
    case daily = 24
    case weekly = 168
    case manual = 0

    public var id: Int {
        rawValue
    }
}

/// Persisted auto-update configuration shared between AppState and SparkleUpdaterService.
public struct AutoUpdateSettings: Sendable, Codable, Equatable {
    public static let defaultStableFeedURL =
        "https://github.com/alsyundawy/SparkleSFTP/releases/latest/download/appcast.xml"

    public var automaticallyChecks: Bool
    public var automaticallyDownloads: Bool
    public var checkFrequency: UpdateCheckFrequency
    public var channel: AutoUpdateChannel
    public var customFeedURL: String
    public var lastCheckedAt: Date?

    public init(
        automaticallyChecks: Bool = true,
        automaticallyDownloads: Bool = false,
        checkFrequency: UpdateCheckFrequency = .daily,
        channel: AutoUpdateChannel = .stable,
        customFeedURL: String = AutoUpdateSettings.defaultStableFeedURL,
        lastCheckedAt: Date? = nil
    ) {
        self.automaticallyChecks = automaticallyChecks
        self.automaticallyDownloads = automaticallyDownloads
        self.checkFrequency = checkFrequency
        self.channel = channel
        self.customFeedURL = customFeedURL
        self.lastCheckedAt = lastCheckedAt
    }

    public var isOverdue: Bool {
        guard automaticallyChecks, checkFrequency.rawValue > 0 else { return false }
        guard let lastCheckedAt else { return true }
        let interval = TimeInterval(checkFrequency.rawValue * 3600)
        return Date().timeIntervalSince(lastCheckedAt) >= interval
    }
}

/// Live status reported back to Preferences UI during update checks.
public enum AutoUpdateCheckStatus: Sendable, Equatable {
    case idle
    case checking
    case upToDate(version: String)
    case updateAvailable(version: String, releaseURL: URL, notes: String)
    case sparkleNativeTriggered
    case failed(reason: String)
}
