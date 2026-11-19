import SparkleDesignSystem
import SwiftUI
import UniformTypeIdentifiers

struct NotepadExportFileDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.plainText, .data]
    }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// Minimalist Notepad2-inspired multi-tab text/code editor embedded in SparkleSFTP.
public struct InternalEditorView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var editorManager: EditorSessionManager
    @State private var isPickingOpenFile = false
    @State private var isPickingSaveAs = false
    @State private var goToLineInput = "1"
    @State private var matchCountNotice: String?

    public init(appState: AppState) {
        self.appState = appState
        editorManager = appState.editorManager
    }

    private var strings: AppStrings {
        appState.strings
    }

    public var body: some View {
        let palette = appState.activePalette
        VStack(spacing: 0) {
            InternalEditorToolbar(
                appState: appState,
                editorManager: editorManager,
                isPickingOpenFile: $isPickingOpenFile,
                isPickingSaveAs: $isPickingSaveAs,
                goToLineInput: $goToLineInput
            )

            if editorManager.isFindBarVisible {
                InternalEditorFindBarView(
                    editorManager: editorManager,
                    strings: strings,
                    palette: palette,
                    matchCountNotice: $matchCountNotice
                )
            }

            editorCanvas(palette: palette)
        }
        .sparkleWorkspaceSurface(palette, useCanvas: true)
        .background(SparkleWindowConfigurator(palette: palette, allowFullScreen: true))
        .onReceive(NotificationCenter.default.publisher(for: .sparklePreferencesDidChange)) { notification in
            if (notification.object as? UUID) != appState.windowInstanceID {
                appState.reloadPreferencesFromNotification()
            }
        }
        .onAppear { editorManager.ensureAtLeastOneDocument() }
        .fileImporter(
            isPresented: $isPickingOpenFile,
            allowedContentTypes: [.text, .plainText, .sourceCode, .xml, .json, .data],
            allowsMultipleSelection: true
        ) { result in
            if case let .success(urls) = result {
                for url in urls {
                    try? editorManager.openLocalFile(at: url)
                }
            }
        }
        .fileExporter(
            isPresented: $isPickingSaveAs,
            document: makeExportDocument(),
            contentType: .plainText,
            defaultFilename: editorManager.activeDocument?.title ?? "Untitled.txt"
        ) { result in
            if case let .success(url) = result {
                Task { await appState.saveActiveEditorDocumentAs(url: url) }
            }
        }
        .sheet(isPresented: $editorManager.isFindReplaceDialogVisible) {
            FindReplaceDialogView(
                editorManager: editorManager,
                strings: strings,
                palette: palette,
                isPresented: $editorManager.isFindReplaceDialogVisible
            )
        }
        .sheet(isPresented: $editorManager.isMacroConsoleVisible) {
            LuaConsoleSheet(
                editorManager: editorManager,
                palette: palette,
                strings: strings,
                isPresented: $editorManager.isMacroConsoleVisible
            )
        }
    }

    @ViewBuilder
    private func editorCanvas(palette: SparkleThemePalette) -> some View {
        if let doc = editorManager.activeDocument {
            NotepadTextView(
                content: activeContentBinding(docID: doc.id),
                cursor: activeCursorBinding(docID: doc.id),
                selectionLength: activeSelectionBinding(docID: doc.id),
                documentID: doc.id,
                syntax: doc.resolvedSyntax,
                palette: palette,
                fontSize: editorManager.fontSize,
                wordWrap: editorManager.wordWrap,
                showLineNumbers: editorManager.showLineNumbers,
                showWhitespace: editorManager.showWhitespace,
                isReadOnly: doc.isReadOnly,
                proxy: editorManager.textViewProxy
            )
            InternalEditorStatusBarView(
                editorManager: editorManager,
                document: doc,
                strings: strings,
                palette: palette
            )
        } else {
            Spacer()
            Button(strings.t("editor.newFile")) {
                editorManager.createUntitledDocument()
            }
            Spacer()
        }
    }

    private func makeExportDocument() -> NotepadExportFileDocument {
        guard let doc = editorManager.activeDocument else {
            return NotepadExportFileDocument(data: Data())
        }
        let normalized = EditorLineEnding.normalize(doc.content, to: doc.lineEnding)
        return NotepadExportFileDocument(data: doc.encoding.encode(normalized))
    }

    private func activeContentBinding(docID: UUID) -> Binding<String> {
        Binding(
            get: { editorManager.documents.first { $0.id == docID }?.content ?? "" },
            set: { newValue in
                editorManager.updateActiveDocument { doc in
                    if doc.id == docID {
                        doc.content = newValue
                    }
                }
            }
        )
    }

    private func activeCursorBinding(docID: UUID) -> Binding<EditorCursorLocation> {
        Binding(
            get: { editorManager.documents.first { $0.id == docID }?.cursor ?? EditorCursorLocation() },
            set: { newValue in
                editorManager.updateActiveDocument { doc in
                    if doc.id == docID {
                        doc.cursor = newValue
                    }
                }
            }
        )
    }

    private func activeSelectionBinding(docID: UUID) -> Binding<Int> {
        Binding(
            get: { editorManager.documents.first { $0.id == docID }?.selectionLength ?? 0 },
            set: { newValue in
                editorManager.updateActiveDocument { doc in
                    if doc.id == docID {
                        doc.selectionLength = newValue
                    }
                }
            }
        )
    }
}
