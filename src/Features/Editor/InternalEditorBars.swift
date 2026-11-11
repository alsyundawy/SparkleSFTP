import SparkleDesignSystem
import SwiftUI

struct InternalEditorFindBarView: View {
    @ObservedObject var editorManager: EditorSessionManager
    let strings: AppStrings
    let palette: SparkleThemePalette
    @Binding var matchCountNotice: String?

    var body: some View {
        HStack(spacing: SparkleTheme.Spacing.small) {
            TextField(strings.t("editor.findPlaceholder"), text: $editorManager.findQuery.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 200)
                .onSubmit {
                    matchCountNotice = "\(editorManager.findMatch(forward: true))"
                }

            TextField(strings.t("editor.replacePlaceholder"), text: $editorManager.findQuery.replaceText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 180)

            Toggle(strings.t("editor.matchCase"), isOn: $editorManager.findQuery.matchCase)
                .toggleStyle(.button)
                .controlSize(.small)
            Toggle(strings.t("editor.regex"), isOn: $editorManager.findQuery.useRegex)
                .toggleStyle(.button)
                .controlSize(.small)

            Button(strings.t("editor.findPrev")) {
                matchCountNotice = "\(editorManager.findMatch(forward: false))"
            }
            Button(strings.t("editor.findNext")) {
                matchCountNotice = "\(editorManager.findMatch(forward: true))"
            }
            Button(strings.t("editor.replaceOne")) {
                editorManager.replaceCurrentMatch()
            }
            Button(strings.t("editor.replaceAll")) {
                matchCountNotice = "\(editorManager.replaceAllMatches())"
            }

            if let matchCountNotice {
                Text("(\(matchCountNotice))")
                    .font(SparkleTheme.Typography.caption)
                    .foregroundStyle(palette.secondaryTextColor)
            }
            Spacer()
            Button {
                editorManager.isFindBarVisible = false
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, SparkleTheme.Spacing.small)
        .padding(.vertical, 6)
        .background(palette.windowColor)
    }
}

struct InternalEditorStatusBarView: View {
    @ObservedObject var editorManager: EditorSessionManager
    let document: EditorDocument
    let strings: AppStrings
    let palette: SparkleThemePalette

    var body: some View {
        HStack(spacing: SparkleTheme.Spacing.medium) {
            Text(
                "Ln \(document.cursor.line), Col \(document.cursor.column) · "
                    + "\(strings.t("editor.sel")) \(document.selectionLength)"
            )
            .font(SparkleTheme.Typography.monoSmall)

            Text(
                "\(document.lineCount) \(strings.t("editor.lines")) · "
                    + "\(document.byteCount) \(strings.t("editor.bytes"))"
            )
            .font(SparkleTheme.Typography.caption)
            .foregroundStyle(palette.secondaryTextColor)

            locationLabel
            Spacer()
            statusBadges
            formatPickers
        }
        .padding(.horizontal, SparkleTheme.Spacing.small)
        .padding(.vertical, 5)
        .background(palette.windowColor)
        .foregroundStyle(palette.primaryTextColor)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(palette.borderColor),
            alignment: .top
        )
    }

    @ViewBuilder
    private var locationLabel: some View {
        if let remotePath = document.remotePath {
            Text("\(document.remoteHost ?? "remote"):\(remotePath.rawValue)")
                .font(SparkleTheme.Typography.monoSmall)
                .foregroundStyle(palette.accentColor)
                .lineLimit(1)
        } else if let localURL = document.localURL {
            Text(localURL.path)
                .font(SparkleTheme.Typography.monoSmall)
                .foregroundStyle(palette.secondaryTextColor)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var statusBadges: some View {
        if document.isReadOnly {
            StatusPill(
                title: strings.t("editor.statusReadOnly"),
                systemImage: "lock.fill",
                tint: SparkleTheme.Colors.warning
            )
        }
        Text(document.isDirty ? strings.t("editor.statusModified") : strings.t(document.syncStatusKey))
            .font(SparkleTheme.Typography.caption)
            .foregroundStyle(document.isDirty ? SparkleTheme.Colors.warning : palette.secondaryTextColor)
    }

    @ViewBuilder
    private var formatPickers: some View {
        Picker("", selection: syntaxBinding) {
            ForEach(EditorSyntaxLanguage.allCases) { lang in
                Text(lang.displayName).tag(lang)
            }
        }
        .labelsHidden()
        .frame(width: 110)

        Picker("", selection: encodingBinding) {
            ForEach(EditorTextEncoding.allCases) { enc in
                Text(enc.rawValue).tag(enc)
            }
        }
        .labelsHidden()
        .frame(width: 96)

        Picker("", selection: lineEndingBinding) {
            ForEach(EditorLineEnding.allCases) { eol in
                Text(eol.displayName).tag(eol)
            }
        }
        .labelsHidden()
        .frame(width: 72)
    }

    private var syntaxBinding: Binding<EditorSyntaxLanguage> {
        Binding(
            get: { editorManager.documents.first { $0.id == document.id }?.syntax ?? .auto },
            set: { newValue in
                editorManager.updateActiveDocument { doc in
                    if doc.id == document.id {
                        doc.syntax = newValue
                    }
                }
            }
        )
    }

    private var encodingBinding: Binding<EditorTextEncoding> {
        Binding(
            get: { editorManager.documents.first { $0.id == document.id }?.encoding ?? .utf8 },
            set: { newValue in
                editorManager.updateActiveDocument { doc in
                    if doc.id == document.id {
                        doc.encoding = newValue
                    }
                }
            }
        )
    }

    private var lineEndingBinding: Binding<EditorLineEnding> {
        Binding(
            get: { editorManager.documents.first { $0.id == document.id }?.lineEnding ?? .unixLF },
            set: { newValue in
                editorManager.updateActiveDocument { doc in
                    if doc.id == document.id {
                        doc.lineEnding = newValue
                    }
                }
            }
        )
    }
}
