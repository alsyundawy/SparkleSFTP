import AppKit
import SparkleCore
import SparkleDesignSystem
import SwiftUI

public struct SnippetsSheet: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var searchQuery = ""
    @State private var selectedCategory = "All"
    @State private var newTitle = ""
    @State private var newCommand = ""
    @State private var newCategory = "Custom"
    @State private var showingResetAlert = false
    @State private var copiedSnippetID: UUID?

    public init(appState: AppState) {
        self.appState = appState
    }

    private var availableCategories: [String] {
        let unique = Set(appState.snippets.map(\.category))
        return ["All"] + unique.sorted()
    }

    private var filteredSnippets: [CommandSnippet] {
        appState.snippets.filter { snippet in
            let matchesCategory = (selectedCategory == "All" || snippet.category == selectedCategory)
            guard matchesCategory else { return false }
            let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !query.isEmpty else { return true }
            return snippet.title.lowercased().contains(query)
                || snippet.command.lowercased().contains(query)
                || snippet.category.lowercased().contains(query)
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SparkleTheme.Spacing.small) {
            headerBar
            searchAndCategoryBar
            newSnippetBar
            snippetList
            footerBar
        }
        .padding()
        .frame(width: 640, height: 500)
        .sparkleWorkspaceSurface(appState.activePalette)
        .alert(
            appState.strings.t("snippets.resetDefaults"),
            isPresented: $showingResetAlert
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                Task { await appState.resetSnippetsToDefaults() }
            }
        } message: {
            Text(appState.strings.t("snippets.resetConfirm"))
        }
    }

    private var headerBar: some View {
        HStack {
            Label(appState.strings.t("nav.snippets"), systemImage: "terminal.fill")
                .font(SparkleTheme.Typography.title)
            Spacer()
            Button(appState.strings.t("common.close")) { dismiss() }
        }
    }

    private var searchAndCategoryBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(appState.activePalette.secondaryTextColor)
                TextField(appState.strings.t("snippets.searchPlaceholder"), text: $searchQuery)
                    .textFieldStyle(.roundedBorder)
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(appState.activePalette.secondaryTextColor)
                    }
                    .buttonStyle(.plain)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(availableCategories, id: \.self) { cat in
                        let isSelected = (selectedCategory == cat)
                        Button {
                            selectedCategory = cat
                        } label: {
                            Text(cat == "All" ? appState.strings.t("snippets.allCategories") : cat)
                                .font(SparkleTheme.Typography.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    isSelected
                                        ? appState.activePalette.accentColor.opacity(0.25)
                                        : appState.activePalette.surfaceColor
                                )
                                .foregroundColor(
                                    isSelected
                                        ? appState.activePalette.accentColor
                                        : appState.activePalette.primaryTextColor
                                )
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var newSnippetBar: some View {
        HStack(spacing: 6) {
            TextField(appState.strings.t("snippets.title"), text: $newTitle)
                .frame(width: 140)
            TextField(appState.strings.t("snippets.command"), text: $newCommand)
            TextField(appState.strings.t("snippets.category"), text: $newCategory)
                .frame(width: 100)
            Button(appState.strings.t("common.add")) {
                let title = newTitle
                let cmd = newCommand
                let cat = newCategory.isEmpty ? "Custom" : newCategory
                newTitle = ""
                newCommand = ""
                Task { await appState.addSnippet(title: title, command: cmd, category: cat) }
            }
            .disabled(newTitle.isEmpty || newCommand.isEmpty)
        }
    }

    private var snippetList: some View {
        List(filteredSnippets) { snippet in
            SnippetRowView(
                snippet: snippet,
                appState: appState,
                isCopied: copiedSnippetID == snippet.id,
                onCopy: { copySnippet(snippet) },
                onRun: { runSnippet(snippet) },
                onDelete: {
                    Task { await appState.deleteSnippet(id: snippet.id) }
                }
            )
            .listRowBackground(appState.activePalette.canvasColor)
        }
        .scrollContentBackground(.hidden)
        .background(appState.activePalette.canvasColor)
    }

    private var footerBar: some View {
        HStack {
            Text("\(filteredSnippets.count) / \(appState.snippets.count) snippets")
                .font(SparkleTheme.Typography.caption)
                .foregroundColor(appState.activePalette.secondaryTextColor)
            Spacer()
            Button(appState.strings.t("snippets.resetDefaults")) {
                showingResetAlert = true
            }
            .buttonStyle(.borderless)
            .foregroundColor(appState.activePalette.accentColor)
        }
    }

    private func copySnippet(_ snippet: CommandSnippet) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(snippet.command, forType: .string)
        copiedSnippetID = snippet.id
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if copiedSnippetID == snippet.id {
                copiedSnippetID = nil
            }
        }
    }

    private func runSnippet(_ snippet: CommandSnippet) {
        let active = appState.terminalManager.session(forWorkspaceTabID: appState.activeTabID)
        active?.sendCommand(snippet.command)
        dismiss()
    }
}

private struct SnippetRowView: View {
    let snippet: CommandSnippet
    let appState: AppState
    let isCopied: Bool
    let onCopy: () -> Void
    let onRun: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(snippet.title)
                        .font(SparkleTheme.Typography.headline)
                    Text(snippet.category)
                        .font(SparkleTheme.Typography.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(appState.activePalette.surfaceColor)
                        .foregroundColor(appState.activePalette.secondaryTextColor)
                        .cornerRadius(4)
                }
                Text(snippet.command)
                    .font(SparkleTheme.Typography.monoSmall)
                    .foregroundColor(appState.activePalette.secondaryTextColor)
                    .lineLimit(1)
            }
            Spacer()
            Button(isCopied ? appState.strings.t("snippets.copied") : appState.strings.t("snippets.copy")) {
                onCopy()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button(appState.strings.t("snippets.run")) {
                onRun()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(appState.terminalManager.session(forWorkspaceTabID: appState.activeTabID) == nil)

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }
}
