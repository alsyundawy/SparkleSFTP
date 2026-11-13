import Foundation

/// Represents a persistent directory bookmark for local or remote file systems (v0.5.0).
public struct BookmarkItem: Identifiable, Sendable, Codable, Equatable {
    public let id: UUID
    public var name: String
    public var path: String
    public var hostIdentifier: String?
    public var isRemote: Bool
    public var iconName: String?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        path: String,
        hostIdentifier: String? = nil,
        isRemote: Bool = false,
        iconName: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.hostIdentifier = hostIdentifier
        self.isRemote = isRemote
        self.iconName = iconName
        self.createdAt = createdAt
    }
}
