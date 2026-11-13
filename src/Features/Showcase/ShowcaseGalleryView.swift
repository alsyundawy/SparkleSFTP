import AppKit
import SparkleCore
import SparkleDesignSystem
import SwiftUI

/// Gallery launcher for reviewing all 8 high-fidelity macOS UI/UX showcases ("Sparkle Commander" visual refresh).
/// Activated at runtime via the `--showcase-gallery` or `--mockup-gallery` launch arguments.
public struct ShowcaseGalleryView: View {
    @State private var selectedScreenID: ScreenID = .mainWorkspace
    @State private var selectedPaletteID: String = SparkleThemeCatalog.defaultDark.id
    @State private var activePalette: SparkleThemePalette = SparkleThemeCatalog.defaultDark
    @State private var isDarkMode: Bool = true

    public enum ScreenID: String, CaseIterable, Identifiable {
        case mainWorkspace = "Main Workspace"
        case connectionManager = "Connection Manager"
        case transferQueue = "Transfer Queue"
        case terminal = "Split Terminal"
        case preferencesThemes = "Preferences & Themes"
        case emptyStates = "Empty States"
        case conflictDialog = "Conflict Resolution"
        case dashboard = "Overview Dashboard"

        public var id: String {
            rawValue
        }

        public var iconName: String {
            switch self {
            case .mainWorkspace: return "macwindow.on.rectangle"
            case .connectionManager: return "network"
            case .transferQueue: return "arrow.up.arrow.down.circle"
            case .terminal: return "terminal"
            case .preferencesThemes: return "paintpalette"
            case .emptyStates: return "square.dashed"
            case .conflictDialog: return "exclamationmark.triangle"
            case .dashboard: return "gauge.with.needle"
            }
        }

        public var category: String {
            switch self {
            case .mainWorkspace, .dashboard: return "WORKSPACE"
            case .connectionManager, .terminal: return "CONNECTIONS"
            case .transferQueue, .conflictDialog: return "TRANSFERS"
            case .preferencesThemes, .emptyStates: return "SYSTEM & UX"
            }
        }
    }

    public init() {}

    private var groupedScreens: [(category: String, screens: [ScreenID])] {
        let order = ["WORKSPACE", "CONNECTIONS", "TRANSFERS", "SYSTEM & UX"]
        return order.map { category in
            (category: category, screens: ScreenID.allCases.filter { $0.category == category })
        }
    }

    public var body: some View {
        let tokens = SparkleSemanticTokens(palette: activePalette)

        HSplitView {
            // MARK: - Gallery Sidebar (~220 pt)

            gallerySidebar(tokens: tokens)
                .frame(minWidth: 200, idealWidth: SparkleSemanticTokens.sidebarWidth, maxWidth: 240)

            // MARK: - Selected Showcase View Area

            VStack(spacing: 0) {
                galleryToolbar(tokens: tokens)

                Divider().overlay(tokens.hairlineBorder)

                Group {
                    switch selectedScreenID {
                    case .mainWorkspace:
                        MainWorkspaceShowcase()
                    case .connectionManager:
                        ConnectionManagerShowcase()
                    case .transferQueue:
                        TransferQueueShowcase()
                    case .terminal:
                        TerminalShowcase()
                    case .preferencesThemes:
                        PreferencesThemesShowcase()
                    case .emptyStates:
                        EmptyStateShowcase()
                    case .conflictDialog:
                        ConflictDialogShowcase()
                    case .dashboard:
                        DashboardShowcase()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(minWidth: 780, maxWidth: .infinity)
        }
        .frame(minWidth: 1000, minHeight: 680)
        .environment(\.sparklePalette, activePalette)
        .preferredColorScheme(isDarkMode ? .dark : .light)
        .background(tokens.windowBackground)
    }

    // MARK: - Gallery Sidebar

    private func gallerySidebar(tokens: SparkleSemanticTokens) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            gallerySidebarHeader(tokens: tokens)
            Divider().overlay(tokens.hairlineBorder)
            gallerySidebarList(tokens: tokens)
            Divider().overlay(tokens.hairlineBorder)
            gallerySidebarFooter(tokens: tokens)
        }
        .background(tokens.sidebarBackground)
    }

    private func gallerySidebarHeader(tokens: SparkleSemanticTokens) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 14))
                .sparkleIconContainer(tint: tokens.accent)

            VStack(alignment: .leading, spacing: 1) {
                Text("SparkleSFTP")
                    .font(SparkleSemanticTokens.captionSemiboldFont)
                    .foregroundStyle(tokens.primaryText)
                Text("v0.4.1 Showcase Gallery")
                    .font(.system(size: 10))
                    .foregroundStyle(tokens.secondaryText)
            }
            Spacer()
        }
        .padding(SparkleSemanticTokens.spacingSm)
        .background(tokens.elevatedHeaderBackground)
    }

    private func gallerySidebarList(tokens: SparkleSemanticTokens) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(groupedScreens, id: \.category) { group in
                    Text(group.category)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(tokens.tertiaryText)
                        .padding(.horizontal, SparkleSemanticTokens.spacingSm)
                        .padding(.top, 10)
                        .padding(.bottom, 2)

                    ForEach(group.screens) { screen in
                        gallerySidebarRow(screen: screen, tokens: tokens)
                    }
                }
            }
            .padding(.horizontal, SparkleSemanticTokens.spacingSm)
            .padding(.vertical, 4)
        }
    }

    private func gallerySidebarRow(screen: ScreenID, tokens: SparkleSemanticTokens) -> some View {
        let isSelected = (selectedScreenID == screen)
        let font = isSelected ? SparkleSemanticTokens.captionSemiboldFont
            : SparkleSemanticTokens.captionFont

        return Button {
            selectedScreenID = screen
        } label: {
            HStack(spacing: 8) {
                Image(systemName: screen.iconName)
                    .font(.system(size: 11))
                    .sparkleIconContainer(tint: isSelected ? tokens.accent : tokens.secondaryText)

                Text(screen.rawValue)
                    .font(font)
                    .foregroundStyle(isSelected ? tokens.primaryText : tokens.secondaryText)

                Spacer()

                if isSelected {
                    Circle()
                        .fill(tokens.accent)
                        .frame(width: 5, height: 5)
                }
            }
            .padding(.horizontal, SparkleSemanticTokens.spacingSm)
            .frame(height: SparkleSemanticTokens.sidebarRowHeight)
            .background(
                RoundedRectangle(cornerRadius: SparkleSemanticTokens.rowCornerRadius, style: .continuous)
                    .fill(isSelected ? tokens.rowSelectionBackground : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private func gallerySidebarFooter(tokens: SparkleSemanticTokens) -> some View {
        HStack {
            Text("Tone:")
                .font(SparkleSemanticTokens.captionFont)
                .foregroundStyle(tokens.secondaryText)

            Picker("Theme Tone", selection: $isDarkMode) {
                Text("Dark").tag(true)
                Text("Light").tag(false)
            }
            .pickerStyle(.segmented)
            .onChange(of: isDarkMode) { newValue in
                activePalette = newValue ? SparkleThemeCatalog.defaultDark : SparkleThemeCatalog.defaultLight
            }
        }
        .padding(SparkleSemanticTokens.spacingSm)
        .background(tokens.elevatedHeaderBackground)
    }

    // MARK: - Gallery Toolbar

    private func galleryToolbar(tokens: SparkleSemanticTokens) -> some View {
        HStack(spacing: 12) {
            Image(systemName: selectedScreenID.iconName)
                .font(.system(size: 12))
                .foregroundStyle(tokens.accent)

            Text(selectedScreenID.rawValue)
                .font(SparkleSemanticTokens.titleFont)
                .foregroundStyle(tokens.primaryText)

            StatusBadge(title: "v0.4.1 Showcase Preview", iconName: "eye.fill", tint: .blue)

            Spacer()

            Text("Palette:")
                .font(SparkleSemanticTokens.captionFont)
                .foregroundStyle(tokens.secondaryText)

            Picker("Palette", selection: $selectedPaletteID) {
                ForEach(SparkleThemeCatalog.builtInPalettes) { pal in
                    Text(pal.displayName).tag(pal.id)
                }
            }
            .frame(width: 150)
            .onChange(of: selectedPaletteID) { newID in
                if let newPal = SparkleThemeCatalog.findBuiltInPalette(id: newID) {
                    activePalette = newPal
                    isDarkMode = newPal.isDark
                }
            }
        }
        .padding(.horizontal, SparkleSemanticTokens.spacingMd)
        .padding(.vertical, 6)
        .background(tokens.elevatedHeaderBackground)
    }
}

/// Backward compatibility alias for ShowcaseGalleryView.
public typealias MockupGalleryView = ShowcaseGalleryView

// MARK: - Xcode Previews (1280×800)

#if DEBUG
    struct ShowcaseGalleryView_Previews: PreviewProvider {
        @MainActor
        static var previews: some View {
            Group {
                ShowcaseGalleryView()
                    .environment(\.sparklePalette, SparkleThemeCatalog.defaultDark)
                    .preferredColorScheme(.dark)
                    .previewDisplayName("Showcase Gallery Dark (1280×800)")

                ShowcaseGalleryView()
                    .environment(\.sparklePalette, SparkleThemeCatalog.defaultLight)
                    .preferredColorScheme(.light)
                    .previewDisplayName("Showcase Gallery Light (1280×800)")
            }
            .frame(width: 1280, height: 800)
        }
    }
#endif
