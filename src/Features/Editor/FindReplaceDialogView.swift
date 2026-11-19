import AppKit
import SparkleDesignSystem
import SwiftUI

/// Active tab mode in the Find / Replace / Mark dialog hub.
public enum FindReplaceTab: String, CaseIterable, Identifiable {
    case find = "Find"
    case replace = "Replace"
    case mark = "Mark"

    public var id: String { rawValue }
}

/// Standalone Find, Replace & Mark Hub conforming to classic Notepad++ / Notepad2 ergonomics.
public struct FindReplaceDialogView: View {
    @ObservedObject var editorManager: EditorSessionManager
    let strings: AppStrings
    let palette: SparkleThemePalette
    @Binding var isPresented: Bool

    @State private var selectedTab: FindReplaceTab = .find
    @State private var statusMessage: String?

    public init(
        editorManager: EditorSessionManager,
        strings: AppStrings,
        palette: SparkleThemePalette,
        isPresented: Binding<Bool>
    ) {
        self.editorManager = editorManager
        self.strings = strings
        self.palette = palette
        self._isPresented = isPresented
    }

    public var body: some View {
        VStack(spacing: SparkleTheme.Spacing.small) {
            headerBar
            tabPicker
            inputSection
            optionsSection
            Divider()
            actionButtonsGroup
            statusBar
        }
        .padding(SparkleTheme.Spacing.medium)
        .frame(width: 440, height: 360)
        .sparkleWorkspaceSurface(palette)
    }

    private var headerBar: some View {
        HStack {
            Text(selectedTab.rawValue)
                .font(SparkleTheme.Typography.title)
                .foregroundStyle(palette.primaryTextColor)
            Spacer()
            ModalCloseButton {
                isPresented = false
            }
        }
    }

    private var tabPicker: some View {
        Picker("Mode", selection: $selectedTab) {
            ForEach(FindReplaceTab.allCases) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Find:")
                    .font(SparkleTheme.Typography.body)
                    .frame(width: 60, alignment: .trailing)
                TextField("Search query", text: $editorManager.findQuery.searchText)
                    .textFieldStyle(.roundedBorder)
                    .font(SparkleTheme.Typography.monoSmall)
                    .onSubmit { executePrimaryAction() }
            }

            if selectedTab == .replace {
                HStack {
                    Text("Replace:")
                        .font(SparkleTheme.Typography.body)
                        .frame(width: 60, alignment: .trailing)
                    TextField("Replace string", text: $editorManager.findQuery.replaceText)
                        .textFieldStyle(.roundedBorder)
                        .font(SparkleTheme.Typography.monoSmall)
                }
            }
        }
    }

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: SparkleTheme.Spacing.medium) {
                Toggle("Match case (Aa)", isOn: $editorManager.findQuery.matchCase)
                Toggle("Whole word (\\b)", isOn: $editorManager.findQuery.wholeWord)
            }
            .font(SparkleTheme.Typography.caption)

            HStack(spacing: SparkleTheme.Spacing.medium) {
                Toggle("Regular expression (.*)", isOn: $editorManager.findQuery.useRegex)
                Toggle("Wrap around (↩)", isOn: $editorManager.findQuery.wrapAround)
            }
            .font(SparkleTheme.Typography.caption)

            if selectedTab == .find {
                HStack(spacing: 8) {
                    Text("Direction:")
                        .font(SparkleTheme.Typography.caption)
                    Picker("", selection: $editorManager.findQuery.searchUp) {
                        Text("Down").tag(false)
                        Text("Up").tag(true)
                    }
                    .pickerStyle(.radioGroup)
                    .horizontalRadioGroupLayout()
                }
            }
        }
        .padding(.leading, 64)
    }

    @ViewBuilder
    private var actionButtonsGroup: some View {
        switch selectedTab {
        case .find:
            findActionButtons
        case .replace:
            replaceActionButtons
        case .mark:
            markActionButtons
        }
    }

    private var findActionButtons: some View {
        HStack {
            Button("Count") {
                let count = editorManager.findQuery.matchRanges(in: editorManager.activeDocument?.content ?? "").count
                statusMessage = "Found \(count) matches"
            }
            Spacer()
            Button("Find Next") {
                executePrimaryAction()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var replaceActionButtons: some View {
        HStack {
            Button("Replace All") {
                let count = editorManager.replaceAllMatches()
                statusMessage = "Replaced \(count) occurrences"
            }
            Spacer()
            Button("Find Next") {
                executePrimaryAction()
            }
            Button("Replace") {
                editorManager.replaceCurrentMatch()
                statusMessage = "Replaced match"
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var markActionButtons: some View {
        HStack(spacing: 6) {
            Button("Clear All") {
                editorManager.clearAllMarks()
                statusMessage = "Cleared all marks & bookmarks"
            }
            Button("Copy Marked") {
                let count = editorManager.copyMarkedText()
                statusMessage = "Copied \(count) items to clipboard"
            }
            Button("Bookmark") {
                let count = editorManager.bookmarkMatchingLines()
                statusMessage = "Bookmarked \(count) lines"
            }
            Spacer()
            Button("Mark All") {
                let count = editorManager.markAllMatches()
                statusMessage = "Marked \(count) ranges"
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var statusBar: some View {
        HStack {
            if let statusMessage {
                Text(statusMessage)
                    .font(SparkleTheme.Typography.caption)
                    .foregroundStyle(palette.accentColor)
            }
            Spacer()
        }
        .frame(height: 16)
    }

    private func executePrimaryAction() {
        let count = editorManager.findMatch(forward: !editorManager.findQuery.searchUp)
        statusMessage = count > 0 ? "Match found (\(count) total)" : "No matches found"
    }
}
