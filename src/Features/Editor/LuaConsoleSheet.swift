import SparkleDesignSystem
import SwiftUI

/// Interactive sandboxed Lua macro and script automation sheet (Task 12.2).
public struct LuaConsoleSheet: View {
    @ObservedObject var editorManager: EditorSessionManager
    let palette: SparkleThemePalette
    let strings: AppStrings
    @Binding var isPresented: Bool

    @State private var selectedPresetID: String = "upper_selection"
    @State private var scriptText: String = EditorMacroEngine.builtInPresets.first?.script ?? ""
    @State private var logHistory: [String] = ["Ready. Select a preset or type a macro script."]
    @State private var statusMessage: String?

    public init(
        editorManager: EditorSessionManager,
        palette: SparkleThemePalette,
        strings: AppStrings,
        isPresented: Binding<Bool>
    ) {
        self.editorManager = editorManager
        self.palette = palette
        self.strings = strings
        _isPresented = isPresented
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider().foregroundStyle(Color(hex: "#333842"))
            presetSelectorBar
            Divider().foregroundStyle(Color(hex: "#333842"))
            scriptEditorPane
            Divider().foregroundStyle(Color(hex: "#333842"))
            logOutputDrawer
            Divider().foregroundStyle(Color(hex: "#333842"))
            footerActionBar
        }
        .frame(width: 620, height: 500)
        .background(palette.canvasColor)
    }

    private var headerBar: some View {
        HStack(spacing: SparkleTheme.Spacing.small) {
            Image(systemName: "curlybraces")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(palette.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("Lua Macro & Automation Console")
                    .font(SparkleTheme.Typography.headline)
                    .foregroundStyle(palette.primaryTextColor)
                Text("Sandboxed Editor Automation (⌘K)")
                    .font(SparkleTheme.Typography.caption)
                    .foregroundStyle(palette.secondaryTextColor)
            }

            Spacer()

            ModalCloseButton {
                isPresented = false
            }
        }
        .padding(SparkleTheme.Spacing.medium)
        .background(palette.surfaceColor)
    }

    private var presetSelectorBar: some View {
        HStack(spacing: SparkleTheme.Spacing.small) {
            Text("Preset:")
                .font(SparkleTheme.Typography.caption)
                .foregroundStyle(palette.secondaryTextColor)

            Picker("Preset", selection: $selectedPresetID) {
                ForEach(EditorMacroEngine.builtInPresets) { preset in
                    Text(preset.name).tag(preset.id)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 220)
            .onChange(of: selectedPresetID) { newID in
                if let found = EditorMacroEngine.builtInPresets.first(where: { $0.id == newID }) {
                    scriptText = found.script
                    statusMessage = found.summary
                }
            }

            if let status = statusMessage {
                Text(status)
                    .font(SparkleTheme.Typography.caption)
                    .foregroundStyle(palette.accentColor)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, SparkleTheme.Spacing.medium)
        .padding(.vertical, 6)
        .background(palette.surfaceColor.opacity(0.6))
    }

    private var scriptEditorPane: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Script Editor")
                .font(SparkleTheme.Typography.caption)
                .foregroundStyle(palette.secondaryTextColor)
                .padding(.horizontal, SparkleTheme.Spacing.medium)
                .padding(.top, 6)

            TextEditor(text: $scriptText)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(SparkleTheme.Spacing.small)
                .background(Color(hex: "#1e1e1e"))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(hex: "#3c3c3c"), lineWidth: 1)
                )
                .padding(.horizontal, SparkleTheme.Spacing.medium)
                .padding(.bottom, 6)
        }
    }

    private var logOutputDrawer: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Execution Logs & Output")
                    .font(SparkleTheme.Typography.caption)
                    .foregroundStyle(palette.secondaryTextColor)
                Spacer()
                Button("Clear Logs") {
                    logHistory.removeAll()
                }
                .buttonStyle(.borderless)
                .font(SparkleTheme.Typography.caption)
                .foregroundStyle(palette.secondaryTextColor)
            }
            .padding(.horizontal, SparkleTheme.Spacing.medium)
            .padding(.top, 4)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(logHistory.enumerated()), id: \.offset) { _, entry in
                        Text(entry)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(
                                entry.contains("Error") || entry.contains("Alert") ?
                                    Color.red : palette.primaryTextColor
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(6)
            }
            .frame(height: 100)
            .background(Color(hex: "#181818"))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(hex: "#333333"), lineWidth: 1)
            )
            .padding(.horizontal, SparkleTheme.Spacing.medium)
            .padding(.bottom, 6)
        }
    }

    private var footerActionBar: some View {
        HStack {
            Button("Reset to Default") {
                if let found = EditorMacroEngine.builtInPresets.first(where: { $0.id == selectedPresetID }) {
                    scriptText = found.script
                }
            }
            .buttonStyle(.bordered)

            Spacer()

            Button("Run Macro") {
                executeMacro()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: [.command])
        }
        .padding(SparkleTheme.Spacing.medium)
        .background(palette.surfaceColor)
    }

    private func executeMacro() {
        guard let doc = editorManager.activeDocument else {
            logHistory.append("Error: No active document found.")
            return
        }

        let selection = editorManager.textViewProxy.selectedString()
        let result = EditorMacroEngine.execute(
            script: scriptText,
            initialText: doc.content,
            selection: selection,
            cursorLine: doc.cursor.line
        )

        for log in result.logMessages {
            logHistory.append(log)
        }

        if result.isSuccess {
            editorManager.updateActiveDocument { activeDoc in
                activeDoc.content = result.outputText
                activeDoc.syncStatusKey = "editor.statusModified"
            }
            if result.zoomDelta != 0 {
                editorManager.fontSize = max(9, min(36, editorManager.fontSize + result.zoomDelta))
            }
            logHistory.append("Success: Macro executed successfully.")
        } else if let err = result.errorMessage {
            logHistory.append("Failed: \(err)")
        }
    }
}
