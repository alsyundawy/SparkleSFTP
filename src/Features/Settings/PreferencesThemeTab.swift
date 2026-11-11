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

struct PreferencesThemeTab: View {
    @ObservedObject var appState: AppState
    @State private var selectedFamily = "All"
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

    private var filteredThemes: [SparkleThemePalette] {
        appState.availableThemes.filter { palette in
            selectedFamily == "All" || palette.family == selectedFamily
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SparkleTheme.Spacing.medium) {
            HStack {
                Picker(strings.t("prefs.themeMode"), selection: $appState.appearanceMode) {
                    Text(strings.t("prefs.modeAuto")).tag(ThemeAppearanceMode.auto)
                    Text(strings.t("prefs.modeLight")).tag(ThemeAppearanceMode.light)
                    Text(strings.t("prefs.modeDark")).tag(ThemeAppearanceMode.dark)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)

                Spacer()

                Picker(strings.t("prefs.themeFamily"), selection: $selectedFamily) {
                    Text(strings.t("prefs.allFamilies")).tag("All")
                    ForEach(families.filter { $0 != "All" }, id: \.self) { family in
                        Text(family).tag(family)
                    }
                }
                .frame(width: 190)
            }

            List(filteredThemes) { palette in
                themeRow(palette)
                    .listRowBackground(appState.activePalette.canvasColor)
            }
            .scrollContentBackground(.hidden)
            .background(appState.activePalette.canvasColor)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(appState.activePalette.borderColor, lineWidth: 1)
            )

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
        .padding(.vertical, SparkleTheme.Spacing.small)
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
            document: ThemeSampleExportDocument(palette: appState.activePalette),
            contentType: .json,
            defaultFilename: "\(appState.activePalette.id)-theme.json"
        ) { _ in }
        .sparkleWorkspaceSurface(appState.activePalette)
    }

    private func themeRow(_ palette: SparkleThemePalette) -> some View {
        let isSelected = appState.activePalette.id == palette.id
        return HStack(spacing: SparkleTheme.Spacing.medium) {
            HStack(spacing: 3) {
                swatch(palette.windowHex)
                swatch(palette.canvasHex)
                swatch(palette.keywordHex)
                swatch(palette.functionHex)
                swatch(palette.stringHex)
            }
            .padding(3)
            .background(Color(hex: palette.canvasHex))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(hex: palette.borderHex), lineWidth: 1))

            VStack(alignment: .leading, spacing: 2) {
                Text(palette.displayName).font(SparkleTheme.Typography.headline)
                Text("\(palette.family) · \(palette.isDark ? "Dark" : "Light")")
                    .font(SparkleTheme.Typography.caption)
                    .foregroundStyle(appState.activePalette.secondaryTextColor)
            }

            Spacer()

            let ratio = String(format: "%.1f:1", palette.primaryContrastRatio)
            StatusPill(
                title: palette.meetsWCAGAA ? "\(ratio) AA" : ratio,
                systemImage: palette.meetsWCAGAA ? "checkmark.circle.fill" : "exclamationmark.triangle",
                tint: palette.meetsWCAGAA ? SparkleTheme.Colors.success : SparkleTheme.Colors.warning
            )

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(appState.activePalette.accentColor)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            appState.selectTheme(palette)
        }
    }

    private func swatch(_ hex: String) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color(hex: hex))
            .frame(width: 12, height: 18)
    }
}
