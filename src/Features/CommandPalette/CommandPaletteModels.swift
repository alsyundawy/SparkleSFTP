import Foundation

/// Categorization of items available in the Command Palette (⌘⇧P).
public enum CommandPaletteCategory: String, Sendable, CaseIterable {
    case navigation
    case connection
    case bookmark
    case setting
    case action

    public var title: String {
        switch self {
        case .navigation: return "Navigation"
        case .connection: return "Connections"
        case .bookmark: return "Bookmarks"
        case .setting: return "Settings"
        case .action: return "Actions"
        }
    }

    public var systemImage: String {
        switch self {
        case .navigation: return "arrow.turn.up.right"
        case .connection: return "server.rack"
        case .bookmark: return "bookmark.fill"
        case .setting: return "gearshape.fill"
        case .action: return "command"
        }
    }
}

/// Searchable item actionable from the Command Palette.
public struct CommandPaletteItem: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let category: CommandPaletteCategory
    public let shortcutHint: String?
    public let action: @MainActor @Sendable () -> Void

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        category: CommandPaletteCategory,
        shortcutHint: String? = nil,
        action: @escaping @MainActor @Sendable () -> Void
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.category = category
        self.shortcutHint = shortcutHint
        self.action = action
    }
}
