import AppKit
import SparkleDesignSystem
import SwiftUI
import UniformTypeIdentifiers

struct LocaleExportDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.json]
    }

    var data: Data

    init(document: LocaleDocument) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        data = (try? encoder.encode(document)) ?? Data("{}".utf8)
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct PreferencesLocalizationTab: View {
    @ObservedObject var appState: AppState
    @State private var isImportingLocale = false
    @State private var isExportingLocale = false

    private var strings: AppStrings {
        appState.strings
    }

    private var palette: SparkleThemePalette {
        appState.activePalette
    }

    private var selectedLocale: LocaleDocument? {
        appState.availableLocales.first { $0.code == appState.activeLocaleCode }
            ?? appState.availableLocales.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SparkleTheme.Spacing.medium) {
                languageSelectorSection
                coverageSummarySection
                maintenanceSection
            }
            .padding(SparkleTheme.Spacing.medium)
        }
        .background(palette.windowColor)
        .fileImporter(
            isPresented: $isImportingLocale,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            if case let .success(urls) = result, let url = urls.first {
                appState.importLocaleFile(from: url)
            }
        }
        .fileExporter(
            isPresented: $isExportingLocale,
            document: LocaleExportDocument(
                document: selectedLocale ?? LocaleDocument(code: "en", displayName: "English", strings: [:])
            ),
            contentType: .json,
            defaultFilename: "\(appState.activeLocaleCode).json"
        ) { _ in }
    }

    private var languageSelectorSection: some View {
        VStack(alignment: .leading, spacing: SparkleTheme.Spacing.small) {
            HStack {
                Label(strings.t("prefs.language"), systemImage: "globe")
                    .font(SparkleTheme.Typography.title)
                Spacer()
                Picker(
                    strings.t("prefs.language"),
                    selection: Binding(
                        get: { appState.activeLocaleCode },
                        set: { appState.selectLocale(code: $0) }
                    )
                ) {
                    ForEach(appState.availableLocales) { doc in
                        Text("\(doc.displayName) (\(doc.code.uppercased()))").tag(doc.code)
                    }
                }
                .labelsHidden()
                .frame(width: 210)
            }

            Text(strings.t("prefs.languageLayoutHint"))
                .font(SparkleTheme.Typography.caption)
                .foregroundStyle(palette.secondaryTextColor)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], spacing: 10) {
                ForEach(appState.availableLocales) { doc in
                    localeCard(doc)
                }
            }
        }
        .padding(SparkleTheme.Spacing.medium)
        .background(palette.canvasColor)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.borderColor, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func localeCard(_ doc: LocaleDocument) -> some View {
        let isSelected = appState.activeLocaleCode == doc.code
        let coverage = LocalizationCatalog.coveragePercentage(for: doc)
        return Button {
            appState.selectLocale(code: doc.code)
        } label: {
            HStack(spacing: 10) {
                Text(doc.code.uppercased())
                    .font(SparkleTheme.Typography.monoSmall.bold())
                    .foregroundStyle(isSelected ? .white : palette.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(isSelected ? palette.accentColor : palette.accentColor.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 5))

                VStack(alignment: .leading, spacing: 2) {
                    Text(doc.displayName)
                        .font(SparkleTheme.Typography.headline)
                        .foregroundStyle(palette.primaryTextColor)
                    Text(String(format: "%.0f%% · %d keys", coverage, doc.strings.count))
                        .font(SparkleTheme.Typography.caption)
                        .foregroundStyle(palette.secondaryTextColor)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(palette.accentColor)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? palette.accentColor.opacity(0.10) : palette.windowColor)
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(isSelected ? palette.accentColor : palette.borderColor, lineWidth: isSelected ? 1.5 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var coverageSummarySection: some View {
        if let locale = selectedLocale {
            let coverage = LocalizationCatalog.coveragePercentage(for: locale)
            let missing = LocalizationCatalog.missingKeys(for: locale)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(strings.t("prefs.coverage"))
                        .font(SparkleTheme.Typography.headline)
                    Spacer()
                    StatusPill(
                        title: String(format: "%.0f%% (%d keys)", coverage, locale.strings.count),
                        systemImage: "checkmark.seal.fill",
                        tint: missing.isEmpty ? SparkleTheme.Colors.success : SparkleTheme.Colors.warning
                    )
                }
                HStack {
                    Text(strings.t("prefs.missingKeys"))
                        .font(SparkleTheme.Typography.body)
                    Spacer()
                    Text("\(missing.count)")
                        .font(SparkleTheme.Typography.monoSmall)
                        .foregroundStyle(missing.isEmpty ? SparkleTheme.Colors.success : SparkleTheme.Colors.warning)
                }
                if !missing.isEmpty {
                    Text(missing.prefix(8).joined(separator: ", "))
                        .font(SparkleTheme.Typography.monoSmall)
                        .foregroundStyle(palette.secondaryTextColor)
                }
            }
            .padding(SparkleTheme.Spacing.medium)
            .background(palette.canvasColor)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.borderColor, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var maintenanceSection: some View {
        VStack(alignment: .leading, spacing: SparkleTheme.Spacing.small) {
            Text("i18n Maintenance (JSON)")
                .font(SparkleTheme.Typography.headline)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 8) {
                Button(strings.t("prefs.importLocale")) { isImportingLocale = true }
                    .frame(maxWidth: .infinity)
                Button(strings.t("prefs.exportLocale")) { isExportingLocale = true }
                    .frame(maxWidth: .infinity)
                Button(strings.t("prefs.openLocalesFolder")) {
                    try? FileManager.default.createDirectory(
                        at: LocalizationCatalog.customLocalesDirectoryURL,
                        withIntermediateDirectories: true
                    )
                    NSWorkspace.shared.open(LocalizationCatalog.customLocalesDirectoryURL)
                }
                .frame(maxWidth: .infinity)
                Button(strings.t("prefs.reloadLocales")) { appState.reloadLocales() }
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(SparkleTheme.Spacing.medium)
        .background(palette.canvasColor)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.borderColor, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
