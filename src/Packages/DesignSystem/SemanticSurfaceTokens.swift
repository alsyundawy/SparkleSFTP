import AppKit
import SwiftUI

/// Semantic surface and UI/UX design tokens for the "Sparkle Commander" visual refresh.
/// Dynamically resolves all color roles, surfaces, borders, and typography from the active
/// `SparkleThemePalette` and color scheme without hardcoding any hex values.
public struct SparkleSemanticTokens: Sendable, Equatable {
    public let palette: SparkleThemePalette

    public init(palette: SparkleThemePalette) {
        self.palette = palette
    }

    // MARK: - Surfaces & Backgrounds

    /// Near-black or subtle tinted window background resolved from the active palette.
    public var windowBackground: Color {
        palette.windowColor
    }

    /// Translucent material-style sidebar background with appropriate subtle tinting.
    public var sidebarBackground: Color {
        if palette.isDark {
            return palette.windowColor.opacity(0.85)
        } else {
            return palette.windowColor.opacity(0.92)
        }
    }

    /// Slightly elevated card surface for grouping file panes, forms, and dialog panels.
    public var cardBackground: Color {
        palette.canvasColor
    }

    /// Secondary elevated surface (e.g. headers, search fields, table title bars).
    public var elevatedHeaderBackground: Color {
        if palette.isDark {
            return palette.windowColor.opacity(0.6)
        } else {
            return palette.canvasColor.opacity(0.7)
        }
    }

    /// Hover state background for rows and interactive elements.
    public var rowHoverBackground: Color {
        palette.accentColor.opacity(palette.isDark ? 0.12 : 0.08)
    }

    /// Selection indicator background for active rows or sidebar items.
    public var rowSelectionBackground: Color {
        palette.selectionColor
    }

    // MARK: - Borders & Hairlines

    /// 1 px hairline border with 6–8% white opacity in dark mode or subtle dark opacity in light mode.
    public var hairlineBorder: Color {
        if palette.isDark {
            return Color.white.opacity(0.08)
        } else {
            return palette.borderColor.opacity(0.25)
        }
    }

    /// Focused border for active panes or selected controls.
    public var focusBorder: Color {
        palette.accentColor.opacity(0.75)
    }

    // MARK: - Geometry & Radii

    /// Standard card corner radius (10 pt).
    public static let cardCornerRadius: CGFloat = 10.0

    /// Standard data row and button corner radius (6 pt).
    public static let rowCornerRadius: CGFloat = 6.0

    /// Pill/Capsule corner radius (12 pt).
    public static let pillCornerRadius: CGFloat = 12.0

    /// SF Symbol icon container dimensions (22×22 pt).
    public static let iconContainerSize: CGFloat = 22.0

    /// Standard sidebar width (~220 pt).
    public static let sidebarWidth: CGFloat = 220.0

    /// Standard data row height (44 pt).
    public static let dataRowHeight: CGFloat = 44.0

    /// Standard sidebar row height (28 pt).
    public static let sidebarRowHeight: CGFloat = 28.0

    // MARK: - Spacing Grid (8 pt System)

    public static let gridUnit: CGFloat = 8.0
    public static let spacingXs: CGFloat = 4.0
    public static let spacingSm: CGFloat = 8.0
    public static let spacingMd: CGFloat = 12.0
    public static let spacingLg: CGFloat = 16.0
    public static let spacingXl: CGFloat = 24.0

    // MARK: - Text & Content

    /// Primary text color with verified WCAG 2.1 AA contrast against the active canvas.
    public var primaryText: Color {
        palette.primaryTextColor
    }

    /// Secondary text at approximately 60% opacity for timestamps, sizes, and path subtitles.
    public var secondaryText: Color {
        palette.secondaryTextColor.opacity(0.85)
    }

    /// Tertiary text for disabled or placeholder content.
    public var tertiaryText: Color {
        palette.secondaryTextColor.opacity(0.50)
    }

    /// Primary accent tint for active controls, badges, and progress bars.
    public var accent: Color {
        palette.accentColor
    }

    /// Subtle 15% accent tint for icon background containers.
    public var accentTintSubtle: Color {
        palette.accentColor.opacity(0.15)
    }

    // MARK: - Typography Tokens

    public static let titleFont: Font = .system(size: 15, weight: .semibold, design: .default)
    public static let titleSecondaryFont: Font = .system(size: 11, weight: .regular, design: .default)
    public static let bodyFont: Font = .system(size: 13, weight: .regular, design: .default)
    public static let captionFont: Font = .system(size: 11, weight: .regular, design: .default)
    public static let captionSemiboldFont: Font = .system(size: 11, weight: .semibold, design: .default)
    public static let monoFont: Font = .system(size: 11, weight: .regular, design: .monospaced)
    public static let monoBoldFont: Font = .system(size: 11, weight: .semibold, design: .monospaced)
}

// MARK: - SwiftUI View Helpers

public extension View {
    /// Renders a 22×22 pt rounded-square container for SF Symbol icons with a 15% accent tint.
    func sparkleIconContainer(tint: Color) -> some View {
        frame(width: SparkleSemanticTokens.iconContainerSize, height: SparkleSemanticTokens.iconContainerSize)
            .background(tint.opacity(0.15))
            .foregroundStyle(tint)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    /// Applies standard Sparkle Commander card styling with dynamic hairline border.
    func sparkleCardStyle(tokens: SparkleSemanticTokens) -> some View {
        background(tokens.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: SparkleSemanticTokens.cardCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SparkleSemanticTokens.cardCornerRadius, style: .continuous)
                    .stroke(tokens.hairlineBorder, lineWidth: 1)
            )
    }
}
