import AppKit
import SparkleDesignSystem
import SwiftUI
import UniformTypeIdentifiers

struct ThemeSampleExportDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.json]
    }

    var data: Data

    init(palette: SparkleThemePalette) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        data = (try? encoder.encode(palette)) ?? Data("{}".utf8)
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private enum ThemeToneFilter: String, CaseIterable, Identifiable {
    case all
    case light
    case dark

    var id: String {
        rawValue
    }
}

struct PreferencesThemeTab: View {
    @ObservedObject var appState: AppState
    @State private var selectedFamily = "All"
    @State private var selectedTone: ThemeToneFilter = .all
    @State private var searchText = ""
    @State private var isImportingTheme = false
    @State private var isExportingTheme = false

    private var strings: AppStrings {
        appState.strings
    }

    private var families: [String] {
        var unique: [String] = []
        for palette in appState.availableThemes where !unique.contains(palette.family) {
            unique.append(palette.family)
        }
        return ["All"] + unique
    }

    private var palette: SparkleThemePalette {
        appState.activePalette
    }

    private var filteredThemes: [SparkleThemePalette] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return appState.availableThemes.filter { item in
            let matchesFamily = selectedFamily == "All" || item.family == selectedFamily
            let matchesTone: Bool = switch selectedTone {
            case .all:
                true
            case .light:
                !item.isDark
            case .dark:
                item.isDark
            }
            let matchesSearch = query.isEmpty
                || item.displayName.localizedCaseInsensitiveContains(query)
                || item.family.localizedCaseInsensitiveContains(query)
                || item.id.localizedCaseInsensitiveContains(query)
            return matchesFamily && matchesTone && matchesSearch
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SparkleTheme.Spacing.medium) {
            activePreviewCard
            filterControlsBar
            themeGridScrollView
            actionButtonsBar
        }
        .padding(SparkleTheme.Spacing.small)
        .fileImporter(
            isPresented: $isImportingTheme,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            if case let .success(urls) = result, let url = urls.first {
                appState.importThemeFile(from: url)
            }
        }
        .fileExporter(
            isPresented: $isExportingTheme,
            document: ThemeSampleExportDocument(palette: palette),
            contentType: .json,
            defaultFilename: "\(palette.id)-theme.json"
        ) { _ in }
        .sparkleWorkspaceSurface(palette)
    }

    private var activePreviewCard: some View {
        ActiveThemePreviewCard(palette: palette, strings: strings)
    }

    private var filterControlsBar: some View {
        VStack(alignment: .leading, spacing: SparkleTheme.Spacing.small) {
            modeAndFamilyFilterRow
            searchAndToneFilterRow
        }
    }

    private var modeAndFamilyFilterRow: some View {
        HStack {
            Picker(strings.t("prefs.themeMode"), selection: $appState.appearanceMode) {
                Text(strings.t("prefs.modeAuto")).tag(ThemeAppearanceMode.auto)
                Text(strings.t("prefs.modeLight")).tag(ThemeAppearanceMode.light)
                Text(strings.t("prefs.modeDark")).tag(ThemeAppearanceMode.dark)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 310)

            Spacer()

            Picker(strings.t("prefs.themeFamily"), selection: $selectedFamily) {
                Text(strings.t("prefs.allFamilies")).tag("All")
                ForEach(families.filter { $0 != "All" }, id: \.self) { family in
                    Text(family).tag(family)
                }
            }
            .frame(width: 210)
        }
    }

    private var searchAndToneFilterRow: some View {
        HStack(spacing: SparkleTheme.Spacing.small) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(palette.secondaryTextColor)
                TextField(strings.t("prefs.searchThemes"), text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(palette.secondaryTextColor)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(palette.canvasColor)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(palette.borderColor, lineWidth: 1))

            Picker(strings.t("prefs.allModes"), selection: $selectedTone) {
                Text(strings.t("prefs.allModes")).tag(ThemeToneFilter.all)
                Text(strings.t("prefs.modeLight")).tag(ThemeToneFilter.light)
                Text(strings.t("prefs.modeDark")).tag(ThemeToneFilter.dark)
            }
            .pickerStyle(.segmented)
            .frame(width: 195)

            Text("\(filteredThemes.count)/\(appState.availableThemes.count)")
                .font(SparkleTheme.Typography.monoSmall)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(palette.canvasColor)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(palette.borderColor, lineWidth: 1))
                .foregroundStyle(palette.secondaryTextColor)
        }
    }

    private var themeGridScrollView: some View {
        ScrollView {
            if filteredThemes.isEmpty {
                emptyThemesPlaceholder
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 255), spacing: 10)], spacing: 10) {
                    ForEach(filteredThemes) { item in
                        ThemePaletteCard(
                            item: item,
                            activePalette: palette,
                            strings: strings
                        ) {
                            appState.selectTheme(item)
                        }
                    }
                }
                .padding(SparkleTheme.Spacing.small)
            }
        }
        .background(palette.canvasColor)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.borderColor, lineWidth: 1))
    }

    private var emptyThemesPlaceholder: some View {
        VStack(spacing: SparkleTheme.Spacing.small) {
            Text(strings.t("prefs.themeNoResults"))
                .font(SparkleTheme.Typography.headline)
                .foregroundStyle(palette.secondaryTextColor)
            Button(strings.t("prefs.themeResetFilters")) {
                selectedFamily = "All"
                selectedTone = .all
                searchText = ""
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
        .padding()
    }

    private var actionButtonsBar: some View {
        HStack(spacing: SparkleTheme.Spacing.small) {
            Button(strings.t("prefs.importTheme")) {
                isImportingTheme = true
            }
            Button(strings.t("prefs.exportTheme")) {
                isExportingTheme = true
            }
            Button(strings.t("prefs.openThemesFolder")) {
                try? FileManager.default.createDirectory(
                    at: SparkleThemeStore.customThemesDirectoryURL,
                    withIntermediateDirectories: true
                )
                NSWorkspace.shared.open(SparkleThemeStore.customThemesDirectoryURL)
            }
            Spacer()
            Button(strings.t("prefs.reloadThemes")) {
                appState.reloadThemes()
            }
        }
    }
}

private struct ActiveThemePreviewCard: View {
    let palette: SparkleThemePalette
    let strings: AppStrings

    var body: some View {
        VStack(alignment: .leading, spacing: SparkleTheme.Spacing.small) {
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Circle().fill(Color(hex: "#FF5F56")).frame(width: 9, height: 9)
                    Circle().fill(Color(hex: "#FFBD2E")).frame(width: 9, height: 9)
                    Circle().fill(Color(hex: "#27C93F")).frame(width: 9, height: 9)
                }
                Text(strings.t("prefs.themeActivePreview"))
                    .font(SparkleTheme.Typography.caption)
                    .foregroundStyle(palette.secondaryTextColor)
                Spacer()
                ThemeContrastBadge(item: palette)
            }

            HStack(spacing: SparkleTheme.Spacing.medium) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(palette.displayName)
                        .font(SparkleTheme.Typography.title)
                        .foregroundStyle(palette.primaryTextColor)
                    Text("\(palette.family) · \(strings.t(palette.isDark ? "prefs.modeDark" : "prefs.modeLight"))")
                        .font(SparkleTheme.Typography.caption)
                        .foregroundStyle(palette.secondaryTextColor)
                }
                Spacer()
                HStack(spacing: 5) {
                    Text("sftp").foregroundStyle(Color(hex: palette.keywordHex))
                    Text("connect").foregroundStyle(Color(hex: palette.functionHex))
                    Text("\"root@host\"").foregroundStyle(Color(hex: palette.stringHex))
                    Text(":22").foregroundStyle(Color(hex: palette.numberHex))
                }
                .font(SparkleTheme.Typography.monoSmall)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(palette.windowColor)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(palette.accentColor.opacity(0.45), lineWidth: 1))
            }
            .padding(SparkleTheme.Spacing.small)
            .background(palette.canvasColor)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(palette.borderColor, lineWidth: 1))
        }
        .padding(SparkleTheme.Spacing.medium)
        .background(palette.windowColor)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(palette.borderColor, lineWidth: 1))
    }
}

private struct ThemePaletteCard: View {
    let item: SparkleThemePalette
    let activePalette: SparkleThemePalette
    let strings: AppStrings
    let onSelect: () -> Void

    private var isSelected: Bool {
        activePalette.id == item.id
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    HStack(spacing: 3) {
                        swatch(item.windowHex)
                        swatch(item.canvasHex)
                        swatch(item.accentHex)
                        swatch(item.keywordHex)
                        swatch(item.functionHex)
                        swatch(item.stringHex)
                    }
                    .padding(3)
                    .background(Color(hex: item.canvasHex))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(hex: item.borderHex), lineWidth: 1))

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(activePalette.accentColor)
                    }
                }

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.displayName)
                            .font(SparkleTheme.Typography.headline)
                            .foregroundStyle(activePalette.primaryTextColor)
                            .lineLimit(1)
                        Text("\(item.family) · \(strings.t(item.isDark ? "prefs.modeDark" : "prefs.modeLight"))")
                            .font(SparkleTheme.Typography.caption)
                            .foregroundStyle(activePalette.secondaryTextColor)
                    }
                    Spacer()
                    ThemeContrastBadge(item: item)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? activePalette.accentColor.opacity(0.09) : activePalette.windowColor)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isSelected ? activePalette.accentColor : activePalette.borderColor,
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func swatch(_ hex: String) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color(hex: hex))
            .frame(width: 11, height: 16)
    }
}

private struct ThemeContrastBadge: View {
    let item: SparkleThemePalette

    var body: some View {
        let ratio = String(format: "%.1f:1", item.primaryContrastRatio)
        StatusPill(
            title: item.meetsWCAGAA ? "\(ratio) AA" : ratio,
            systemImage: item.meetsWCAGAA ? "checkmark.circle.fill" : "exclamationmark.triangle",
            tint: item.meetsWCAGAA ? SparkleTheme.Colors.success : SparkleTheme.Colors.warning
        )
    }
}
