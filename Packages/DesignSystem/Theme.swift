import SwiftUI

/// Semantic color and typography design tokens for SparkleSFTP (macOS 13+).
public enum SparkleTheme {
    public enum Colors {
        public static let accent = Color.accentColor
        public static let surface = Color(nsColor: .windowBackgroundColor)
        public static let panelBackground = Color(nsColor: .controlBackgroundColor)
        public static let subtleBorder = Color(nsColor: .separatorColor)
        public static let primaryText = Color(nsColor: .labelColor)
        public static let secondaryText = Color(nsColor: .secondaryLabelColor)

        public static let success = Color.green
        public static let warning = Color.orange
        public static let danger = Color.red
        public static let encryptedBadge = Color.teal
    }

    public enum Typography {
        public static let title = Font.system(size: 16, weight: .semibold, design: .default)
        public static let headline = Font.system(size: 13, weight: .semibold, design: .default)
        public static let body = Font.system(size: 13, weight: .regular, design: .default)
        public static let caption = Font.system(size: 11, weight: .regular, design: .default)
        public static let mono = Font.system(size: 12, weight: .regular, design: .monospaced)
        public static let monoSmall = Font.system(size: 11, weight: .regular, design: .monospaced)
    }

    public enum Spacing {
        public static let xxs: CGFloat = 4
        public static let tiny: CGFloat = 6
        public static let small: CGFloat = 8
        public static let medium: CGFloat = 12
        public static let large: CGFloat = 16
        public static let extraLarge: CGFloat = 24
    }

    public enum Symbols {
        public static let sftp = "lock.shield.fill"
        public static let ftpInsecure = "exclamationmark.triangle.fill"
        public static let folder = "folder.fill"
        public static let file = "doc.fill"
        public static let symlink = "link"
        public static let upload = "arrow.up.circle.fill"
        public static let download = "arrow.down.circle.fill"
        public static let terminal = "terminal.fill"
        public static let sync = "arrow.triangle.2.circlepath"
        public static let connect = "bolt.horizontal.circle.fill"
        public static let disconnect = "xmark.circle.fill"
        public static let key = "key.fill"
        public static let tunnel = "network"
    }
}
