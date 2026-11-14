import AppKit
import SparkleCore
import SparkleDesignSystem
import SparkleFileManager
import SwiftUI

public enum ArchiveSheetMode: Sendable {
    case compress(sourceURLs: [URL])
    case extract(archiveURL: URL)
}

public struct ArchiveSheet: View {
    @ObservedObject var appState: AppState
    let mode: ArchiveSheetMode
    let destinationDirectory: URL
    let onComplete: @Sendable () async -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var format: ArchiveFormat = .zip
    @State private var archiveName: String = ""
    @State private var isExecuting = false
    @State private var errorMessage: String?

    public init(
        appState: AppState,
        mode: ArchiveSheetMode,
        destinationDirectory: URL,
        onComplete: @escaping @Sendable () async -> Void
    ) {
        self.appState = appState
        self.mode = mode
        self.destinationDirectory = destinationDirectory
        self.onComplete = onComplete

        let initialName: String
        switch mode {
        case let .compress(sources):
            let base = sources.first?.deletingPathExtension().lastPathComponent ?? "Archive"
            initialName = "\(base).zip"
        case let .extract(archive):
            initialName = archive.deletingPathExtension().lastPathComponent
        }
        _archiveName = State(initialValue: initialName)
    }

    private var strings: AppStrings {
        appState.strings
    }

    private var has7zz: Bool {
        ArchiveService.find7zBinary() != nil
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SparkleTheme.Spacing.medium) {
            headerView
            contentSection
            if let errorMessage {
                Text(errorMessage)
                    .font(SparkleTheme.Typography.caption)
                    .foregroundStyle(SparkleTheme.Colors.danger)
            }
            Spacer(minLength: 0)
            footerActionView
        }
        .padding(SparkleTheme.Spacing.large)
        .frame(width: 520, height: 380)
        .sparkleWorkspaceSurface(appState.activePalette)
    }

    private var headerView: some View {
        HStack {
            let title = isCompressMode ? strings.t("archive.createTitle") : strings.t("archive.extractTitle")
            Label(title, systemImage: "archivebox.fill")
                .font(SparkleTheme.Typography.title)
            Spacer()
            Button(strings.t("common.close")) { dismiss() }
        }
    }

    private var isCompressMode: Bool {
        if case .compress = mode {
            return true
        }
        return false
    }

    @ViewBuilder
    private var contentSection: some View {
        switch mode {
        case let .compress(sources):
            VStack(alignment: .leading, spacing: 8) {
                Text("\(sources.count) items selected")
                    .font(SparkleTheme.Typography.caption)
                    .foregroundStyle(appState.activePalette.secondaryTextColor)

                TextField(strings.t("archive.namePlaceholder"), text: $archiveName)
                    .textFieldStyle(.roundedBorder)

                Picker(strings.t("archive.format"), selection: $format) {
                    ForEach(ArchiveFormat.allCases) { fmt in
                        if fmt == .sevenZip, !has7zz {
                            Text("\(fmt.displayName) (Requires 7zz)").tag(fmt)
                        } else {
                            Text(fmt.displayName).tag(fmt)
                        }
                    }
                }
                .onChange(of: format) { newFmt in
                    updateArchiveExtension(for: newFmt)
                }
            }
            .padding(SparkleTheme.Spacing.small)
            .background(appState.activePalette.canvasColor)
            .clipShape(RoundedRectangle(cornerRadius: 6))

        case let .extract(archive):
            VStack(alignment: .leading, spacing: 8) {
                Text(archive.lastPathComponent)
                    .font(SparkleTheme.Typography.headline)
                Text("Destination: \(destinationDirectory.path)")
                    .font(SparkleTheme.Typography.caption)
                    .foregroundStyle(appState.activePalette.secondaryTextColor)
            }
            .padding(SparkleTheme.Spacing.small)
            .background(appState.activePalette.canvasColor)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private var footerActionView: some View {
        HStack {
            Spacer()
            Button(strings.t("common.cancel"), role: .cancel) { dismiss() }
            let btnTitle = isCompressMode ? strings.t("archive.compressButton") : strings.t("archive.extractButton")
            Button(btnTitle) {
                executeAction()
            }
            .buttonStyle(.borderedProminent)
            .disabled(isExecuting || (isCompressMode && archiveName.trimmingCharacters(in: .whitespaces).isEmpty))
        }
    }

    private func updateArchiveExtension(for newFormat: ArchiveFormat) {
        let base = (archiveName as NSString).deletingPathExtension
        archiveName = "\(base).\(newFormat.fileExtension)"
    }

    private func executeAction() {
        isExecuting = true
        errorMessage = nil
        let targetFormat = format
        let targetName = archiveName
        let destDir = destinationDirectory

        Task {
            do {
                switch mode {
                case let .compress(sources):
                    let destURL = destDir.appendingPathComponent(targetName)
                    try await ArchiveService.compress(
                        sourceURLs: sources,
                        destinationURL: destURL,
                        format: targetFormat
                    )
                case let .extract(archive):
                    try await ArchiveService.extract(
                        archiveURL: archive,
                        destinationDirectory: destDir
                    )
                }
                await onComplete()
                await MainActor.run {
                    isExecuting = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isExecuting = false
                }
            }
        }
    }
}
