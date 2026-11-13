import SparkleDesignSystem
import SwiftUI

struct InternalEditorToolbar: View {
    @ObservedObject var appState: AppState
    @ObservedObject var editorManager: EditorSessionManager
    @Binding var isPickingOpenFile: Bool
    @Binding var isPickingSaveAs: Bool
    @Binding var goToLineInput: String

    private var strings: AppStrings {
        appState.strings
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                fileGroup
                Divider().frame(height: 18).padding(.horizontal, 3)
                editGroup
                Divider().frame(height: 18).padding(.horizontal, 3)
                findAndToolsGroup
                Divider().frame(height: 18).padding(.horizontal, 3)
                viewGroup
                Divider().frame(height: 18).padding(.horizontal, 3)
                zoomGroup
            }
            .padding(.horizontal, SparkleTheme.Spacing.small)
            .padding(.vertical, 5)
        }
        .background(Color(hex: appState.activePalette.windowHex))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Color(hex: appState.activePalette.borderHex)),
            alignment: .bottom
        )
    }

    @ViewBuilder
    private var fileGroup: some View {
        iconButton("doc.badge.plus", help: strings.t("editor.newFile")) {
            editorManager.createUntitledDocument()
        }
        .keyboardShortcut("n", modifiers: [.command])

        iconButton("folder", help: strings.t("editor.openFile")) {
            isPickingOpenFile = true
        }
        .keyboardShortcut("o", modifiers: [.command])

        iconButton("square.and.arrow.down", help: strings.t("editor.save")) {
            if editorManager.activeDocument?.localURL == nil {
                isPickingSaveAs = true
            } else {
                Task { await appState.saveActiveEditorDocument() }
            }
        }
        .disabled(editorManager.activeDocument == nil || (editorManager.activeDocument?.isReadOnly ?? true))
        .keyboardShortcut("s", modifiers: [.command])

        iconButton("square.and.arrow.down.on.square", help: strings.t("editor.saveAs")) {
            isPickingSaveAs = true
        }
        .disabled(editorManager.activeDocument == nil)

        iconButton("arrow.clockwise", help: strings.t("editor.reload")) {
            Task { await appState.reloadActiveEditorDocument() }
        }
        .disabled(editorManager.activeDocument?.localURL == nil)
    }

    @ViewBuilder
    private var editGroup: some View {
        iconButton("arrow.uturn.backward", help: strings.t("editor.undo")) {
            editorManager.textViewProxy.undo()
        }
        iconButton("arrow.uturn.forward", help: strings.t("editor.redo")) {
            editorManager.textViewProxy.redo()
        }
        iconButton("scissors", help: strings.t("editor.cut")) {
            editorManager.textViewProxy.cut()
        }
        .disabled(editorManager.activeDocument?.isReadOnly ?? false)
        iconButton("doc.on.doc", help: strings.t("editor.copy")) {
            editorManager.textViewProxy.copySelection()
        }
        iconButton("doc.on.clipboard", help: strings.t("editor.paste")) {
            editorManager.textViewProxy.paste()
        }
        .disabled(editorManager.activeDocument?.isReadOnly ?? false)
    }

    @ViewBuilder
    private var findAndToolsGroup: some View {
        toggleIcon(
            "magnifyingglass",
            isOn: $editorManager.isFindBarVisible,
            help: strings.t("editor.findReplace")
        )
        .keyboardShortcut("f", modifiers: [.command])

        iconButton("arrow.right.to.line", help: strings.t("editor.goToLine")) {
            goToLineInput = "\(editorManager.activeDocument?.cursor.line ?? 1)"
            editorManager.isShowingGoToLine = true
        }
        .keyboardShortcut("l", modifiers: [.command])
        .popover(isPresented: $editorManager.isShowingGoToLine) {
            VStack(alignment: .leading, spacing: 8) {
                Text(strings.t("editor.goToLine")).font(SparkleTheme.Typography.headline)
                HStack {
                    TextField("Line #", text: $goToLineInput)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                        .onSubmit {
                            jumpToLine()
                        }
                    Button(strings.t("common.ok")) {
                        jumpToLine()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(SparkleTheme.Spacing.medium)
        }

        Menu {
            Button(strings.t("editor.uppercase")) { editorManager.applyTextTransform(.uppercase) }
            Button(strings.t("editor.lowercase")) { editorManager.applyTextTransform(.lowercase) }
            Button(strings.t("editor.titleCase")) { editorManager.applyTextTransform(.titleCase) }
            Divider()
            Button(strings.t("editor.trimTrailing")) { editorManager.applyTextTransform(.trimTrailingWhitespace) }
            Button(strings.t("editor.sortAsc")) { editorManager.applyTextTransform(.sortLinesAscending) }
            Button(strings.t("editor.sortDesc")) { editorManager.applyTextTransform(.sortLinesDescending) }
        } label: {
            Image(systemName: "textformat")
        }
        .menuStyle(.borderlessButton)
        .frame(width: 28, height: 22)
        .help(strings.t("editor.transforms"))
        .disabled(editorManager.activeDocument?.isReadOnly ?? false)
    }

    @ViewBuilder
    private var viewGroup: some View {
        toggleIcon("arrow.turn.down.left", isOn: $editorManager.wordWrap, help: strings.t("editor.wordWrap"))
        toggleIcon("list.number", isOn: $editorManager.showLineNumbers, help: strings.t("editor.lineNumbers"))
        toggleIcon("paragraphsign", isOn: $editorManager.showWhitespace, help: strings.t("editor.whitespace"))

        let readOnlyBinding = Binding<Bool>(
            get: { editorManager.activeDocument?.isReadOnly ?? false },
            set: { newVal in
                editorManager.updateActiveDocument { $0.isReadOnly = newVal }
            }
        )
        toggleIcon(
            (editorManager.activeDocument?.isReadOnly ?? false) ? "lock.fill" : "lock.open",
            isOn: readOnlyBinding,
            help: strings.t("editor.readOnly")
        )

        iconButton("terminal", help: strings.t("nav.standaloneTerminal")) {
            appState.openStandaloneTerminal()
        }
        .keyboardShortcut("t", modifiers: [.command, .option])
    }

    @ViewBuilder
    private var zoomGroup: some View {
        iconButton("minus.magnifyingglass", help: strings.t("editor.zoomOut")) {
            editorManager.zoomOut()
        }
        Button("\(Int((editorManager.fontSize / 13.0) * 100))%") {
            editorManager.zoomReset()
        }
        .buttonStyle(.borderless)
        .font(SparkleTheme.Typography.monoSmall)
        .help(strings.t("editor.zoomReset"))

        iconButton("plus.magnifyingglass", help: strings.t("editor.zoomIn")) {
            editorManager.zoomIn()
        }

        if let localURL = editorManager.activeDocument?.localURL {
            iconButton("arrow.up.forward.app", help: strings.t("editor.openExternal")) {
                NSWorkspace.shared.open(localURL)
            }
        }
    }

    private func iconButton(_ systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13))
                .frame(width: 24, height: 22)
        }
        .buttonStyle(.borderless)
        .help(help)
        .accessibilityLabel(help)
    }

    private func toggleIcon(_ systemImage: String, isOn: Binding<Bool>, help: String) -> some View {
        Toggle(isOn: isOn) {
            Image(systemName: systemImage)
                .font(.system(size: 13))
                .frame(width: 22, height: 20)
        }
        .toggleStyle(.button)
        .controlSize(.small)
        .help(help)
        .accessibilityLabel(help)
    }

    private func jumpToLine() {
        if let line = Int(goToLineInput.trimmingCharacters(in: .whitespacesAndNewlines)) {
            editorManager.textViewProxy.goToLine(line)
        }
        editorManager.isShowingGoToLine = false
    }
}
