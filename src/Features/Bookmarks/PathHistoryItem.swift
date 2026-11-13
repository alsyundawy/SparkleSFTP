import Foundation

/// Represents a timestamped directory path entry in the 20-item ring buffer history (v0.5.0).
public struct PathHistoryItem: Identifiable, Sendable, Codable, Equatable {
    public let id: UUID
    public let path: String
    public let isRemote: Bool
    public let hostIdentifier: String?
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        path: String,
        isRemote: Bool,
        hostIdentifier: String? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.path = path
        self.isRemote = isRemote
        self.hostIdentifier = hostIdentifier
        self.timestamp = timestamp
    }
}
