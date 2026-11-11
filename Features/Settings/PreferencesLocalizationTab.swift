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

    private var selectedLocale: LocaleDocument? {
        appState.availableLocales.first { $0.code == appState.activeLocaleCode }
            ?? appState.availableLocales.first
    }

    var body: some View {
        Form {
            Section(strings.t("prefs.appearanceAndLang")) {
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

                if let locale = selectedLocale {
                    let coverage = LocalizationCatalog.coveragePercentage(for: locale)
                    let missing = LocalizationCatalog.missingKeys(for: locale)
                    HStack {
                        Text(strings.t("prefs.coverage"))
                        Spacer()
                        Text(String(format: "%.0f%% (%d keys)", coverage, locale.strings.count))
                            .font(SparkleTheme.Typography.monoSmall)
                    }
                    HStack {
                        Text(strings.t("prefs.missingKeys"))
                        Spacer()
                        Text("\(missing.count)")
                            .font(SparkleTheme.Typography.monoSmall)
                            .foregroundStyle(missing.isEmpty ? SparkleTheme.Colors.success : SparkleTheme.Colors
                                .warning)
                    }
                    if !missing.isEmpty {
                        Text(missing.prefix(8).joined(separator: ", "))
                            .font(SparkleTheme.Typography.monoSmall)
                            .foregroundStyle(SparkleTheme.Colors.secondaryText)
                    }
                }
            }

            Section("i18n Maintenance (JSON)") {
                HStack(spacing: SparkleTheme.Spacing.small) {
                    Button(strings.t("prefs.importLocale")) {
                        isImportingLocale = true
                    }
                    Button(strings.t("prefs.exportLocale")) {
                        isExportingLocale = true
                    }
                }
                HStack(spacing: SparkleTheme.Spacing.small) {
                    Button(strings.t("prefs.openLocalesFolder")) {
                        try? FileManager.default.createDirectory(
                            at: LocalizationCatalog.customLocalesDirectoryURL,
                            withIntermediateDirectories: true
                        )
                        NSWorkspace.shared.open(LocalizationCatalog.customLocalesDirectoryURL)
                    }
                    Button(strings.t("prefs.reloadLocales")) {
                        appState.reloadLocales()
                    }
                }
            }
        }
        .formStyle(.grouped)
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
}
