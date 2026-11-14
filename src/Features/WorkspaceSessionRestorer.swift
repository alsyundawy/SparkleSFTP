import Foundation
import SparkleCore

/// Persistent snapshot of an open workspace tab across application restarts.
public struct SavedTabSnapshot: Codable, Sendable, Equatable {
    public let profileID: UUID?
    public let localPath: String?
    public let remotePath: String?
    public let title: String

    public init(
        profileID: UUID? = nil,
        localPath: String? = nil,
        remotePath: String? = nil,
        title: String = "Tab"
    ) {
        self.profileID = profileID
        self.localPath = localPath
        self.remotePath = remotePath
        self.title = title
    }
}

/// Manages workspace session state saving and restoration without automatic connection.
public enum WorkspaceSessionRestorer {
    public static let sessionDefaultsKey = "sparklesftp.workspace.saved_tabs"

    /// Saves open workspace tab snapshots into UserDefaults.
    public static func saveTabs(_ tabs: [SavedTabSnapshot], defaults: UserDefaults = .standard) {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(tabs) {
            defaults.set(data, forKey: sessionDefaultsKey)
        }
    }

    /// Loads saved tab snapshots for restoration on launch (disconnected state).
    public static func loadSavedTabs(defaults: UserDefaults = .standard) -> [SavedTabSnapshot] {
        guard let data = defaults.data(forKey: sessionDefaultsKey) else {
            return []
        }
        let decoder = JSONDecoder()
        return (try? decoder.decode([SavedTabSnapshot].self, from: data)) ?? []
    }

    /// Clears saved session state.
    public static func clearSavedTabs(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: sessionDefaultsKey)
    }
}
