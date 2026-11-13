import AppKit
import SparkleCore
import SparkleDesignSystem
import SwiftUI

private struct PrefCategory: Identifiable {
    let id: String
    let title: String
    let icon: String
    let tint: Color
}

/// High-fidelity Preferences & Themes browser mockup featuring dynamic WCAG 2.1 AA contrast checking.
public struct PreferencesThemesMockup: View {
    @State private var selectedCategory: String = "Themes"
    @State private var toneFilter: ToneFilter = .all
    @State private var selectedThemeID: String = SparkleThemeCatalog.defaultDark.id
    @State private var searchQuery: String = ""

    @Environment(\.sparklePalette) private var palette

    public enum ToneFilter: String, CaseIterable {
        case all = "All"
        case dark = "Dark"
        case light = "Light"
    }

    public init() {}

    private var filteredPalettes: [SparkleThemePalette] {
        SparkleThemeCatalog.builtInPalettes.filter { item in
            let matchesTone: Bool = switch toneFilter {
            case .all: true
            case .dark: item.isDark
            case .light: !item.isDark
            }
            let matchesSearch = searchQuery.isEmpty
                || item.displayName.localizedCaseInsensitiveContains(searchQuery)
                || item.family.localizedCaseInsensitiveContains(searchQuery)
            return matchesTone && matchesSearch
        }
    }

    private var inspectedPalette: SparkleThemePalette {
        SparkleThemeCatalog.builtInPalettes.first { $0.id == selectedThemeID } ?? palette
    }

    public var body: some View {
        let tokens = SparkleSemanticTokens(palette: palette)

        HSplitView {
            preferencesSidebar(tokens: tokens)
                .frame(minWidth: 200, idealWidth: SparkleSemanticTokens.sidebarWidth, maxWidth: 240)

            VStack(spacing: 0) {
                toolbarHeader(tokens: tokens)

                Divider().overlay(tokens.hairlineBorder)

                HSplitView {
                    themeGridBrowser(tokens: tokens)
                        .frame(minWidth: 500, maxWidth: .infinity)

                    ContrastInspectorPanel(
                        palette: inspectedPalette,
                        tokens: tokens
                    )
                    .frame(minWidth: 290, idealWidth: 320, maxWidth: 360)
                }
            }
        }
        .frame(minWidth: 960, minHeight: 620)
        .background(tokens.windowBackground)
    }

    // MARK: - Sidebar

    private func preferencesSidebar(tokens: SparkleSemanticTokens) -> some View {
        let categories = [
            PrefCategory(id: "General", title: "General", icon: "gearshape.fill", tint: .gray),
            PrefCategory(id: "Themes", title: "Appearance & Themes", icon: "paintpalette.fill", tint: .blue),
            PrefCategory(
                id: "Transfers",
                title: "Transfer Engine",
                icon: "arrow.up.arrow.down.circle.fill",
                tint: .indigo
            ),
            PrefCategory(id: "Security", title: "SSH & Keychain", icon: "lock.shield.fill", tint: .green),
            PrefCategory(id: "Localization", title: "Language & Region", icon: "globe", tint: .teal),
            PrefCategory(id: "Updates", title: "Software Updates", icon: "arrow.down.app.fill", tint: .orange)
        ]

        return VStack(alignment: .leading, spacing: 4) {
            Text("PREFERENCES")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tokens.tertiaryText)
                .padding(.horizontal, SparkleSemanticTokens.spacingSm)
                .padding(.top, SparkleSemanticTokens.spacingMd)
                .padding(.bottom, 4)

            ForEach(categories) { cat in
                let isSelected = (selectedCategory == cat.id)
                let font = isSelected ? SparkleSemanticTokens.captionSemiboldFont
                    : SparkleSemanticTokens.bodyFont
                Button {
                    selectedCategory = cat.id
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: cat.icon)
                            .font(.system(size: 11))
                            .sparkleIconContainer(tint: cat.tint)

                        Text(cat.title)
                            .font(font)
                            .foregroundStyle(isSelected ? tokens.accent : tokens.primaryText)

                        Spacer()
                    }
                    .padding(.horizontal, SparkleSemanticTokens.spacingSm)
                    .frame(height: SparkleSemanticTokens.sidebarRowHeight + 4)
                    .background(
                        RoundedRectangle(cornerRadius: SparkleSemanticTokens.rowCornerRadius, style: .continuous)
                            .fill(isSelected ? tokens.rowSelectionBackground : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(SparkleSemanticTokens.spacingSm)
        .background(tokens.sidebarBackground)
    }

    // MARK: - Toolbar Header

    private func toolbarHeader(tokens: SparkleSemanticTokens) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(tokens.secondaryText)
                TextField("Filter 76 themes...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(SparkleSemanticTokens.bodyFont)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(tokens.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(tokens.hairlineBorder, lineWidth: 1))
            .frame(width: 220)

            Spacer()

            Picker("Tone", selection: $toneFilter) {
                ForEach(ToneFilter.allCases, id: \.self) { tone in
                    Text(tone.rawValue).tag(tone)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
        }
        .padding(.horizontal, SparkleSemanticTokens.spacingMd)
        .padding(.vertical, SparkleSemanticTokens.spacingSm)
        .background(tokens.elevatedHeaderBackground)
    }

    // MARK: - Theme Grid Browser

    private func themeGridBrowser(tokens: SparkleSemanticTokens) -> some View {
        let gridCols = [GridItem(.adaptive(minimum: 210, maximum: 260), spacing: 12)]

        return ScrollView {
            LazyVGrid(columns: gridCols, spacing: 12) {
                ForEach(filteredPalettes.prefix(18)) { theme in
                    let isSelected = (selectedThemeID == theme.id)
                    ThemeCardView(
                        theme: theme,
                        isSelected: isSelected,
                        tokens: tokens,
                        onSelect: { selectedThemeID = theme.id }
                    )
                }
            }
            .padding(SparkleSemanticTokens.spacingMd)
        }
    }
}

// MARK: - Theme Card View

private struct ThemeCardView: View {
    let theme: SparkleThemePalette
    let isSelected: Bool
    let tokens: SparkleSemanticTokens
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 10) {
                previewSwatch
                metadataFooter
            }
            .padding(10)
            .background(tokens.cardBackground)
            .clipShape(RoundedRectangle(
                cornerRadius: SparkleSemanticTokens.cardCornerRadius,
                style: .continuous
            ))
            .overlay(
                RoundedRectangle(
                    cornerRadius: SparkleSemanticTokens.cardCornerRadius,
                    style: .continuous
                )
                .stroke(isSelected ? tokens.accent : tokens.hairlineBorder, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var previewSwatch: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Circle().fill(Color.red.opacity(0.8)).frame(width: 6, height: 6)
                Circle().fill(Color.yellow.opacity(0.8)).frame(width: 6, height: 6)
                Circle().fill(Color.green.opacity(0.8)).frame(width: 6, height: 6)
                Spacer()
                Text(theme.isDark ? "DARK" : "LIGHT")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(theme.secondaryTextColor)
            }

            Text("func transferFiles() -> Bool")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(theme.keywordColor)
                .lineLimit(1)

            Text("let target = \"/var/log/nginx\"")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(theme.stringColor)
                .lineLimit(1)
        }
        .padding(8)
        .background(theme.canvasColor)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(theme.borderColor.opacity(0.4), lineWidth: 1)
        )
    }

    private var metadataFooter: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(theme.displayName)
                    .font(SparkleSemanticTokens.captionSemiboldFont)
                    .foregroundStyle(tokens.primaryText)
                    .lineLimit(1)
                Text(theme.family)
                    .font(.system(size: 10))
                    .foregroundStyle(tokens.secondaryText)
            }

            Spacer()

            Text(String(format: "%.1f:1", theme.primaryContrastRatio))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background((theme.meetsWCAGAA ? Color.green : Color.orange).opacity(0.16))
                .foregroundStyle(theme.meetsWCAGAA ? Color.green : Color.orange)
                .clipShape(Capsule())
        }
    }
}

// MARK: - Xcode Previews (1280×800)

#if DEBUG
    struct PreferencesThemesMockup_Previews: PreviewProvider {
        @MainActor
        static var previews: some View {
            Group {
                PreferencesThemesMockup()
                    .environment(\.sparklePalette, SparkleThemeCatalog.defaultDark)
                    .preferredColorScheme(.dark)
                    .previewDisplayName("Preferences & Themes Dark (1280×800)")

                PreferencesThemesMockup()
                    .environment(\.sparklePalette, SparkleThemeCatalog.defaultLight)
                    .preferredColorScheme(.light)
                    .previewDisplayName("Preferences & Themes Light (1280×800)")
            }
            .frame(width: 1280, height: 800)
        }
    }
#endif
