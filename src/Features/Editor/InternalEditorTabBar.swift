import SparkleDesignSystem
import SwiftUI

/// Ergonomic multi-tab bar for the embedded editor supporting status badges, dirty dots, and gestures.
public struct InternalEditorTabBar: View {
    @ObservedObject var editorManager: EditorSessionManager
    let palette: SparkleThemePalette

    public init(editorManager: EditorSessionManager, palette: SparkleThemePalette) {
        self.editorManager = editorManager
        self.palette = palette
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(editorManager.documents) { doc in
                    tabPill(for: doc)
                }
                Spacer(minLength: 24)
            }
            .padding(.horizontal, SparkleTheme.Spacing.small)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                editorManager.createUntitledDocument()
            }
        }
        .background(palette.windowColor)
    }

    private func tabPill(for doc: EditorDocument) -> some View {
        let isSelected = editorManager.activeDocument?.id == doc.id
        return HStack(spacing: 6) {
            tabIndicators(for: doc)
            tabTitle(for: doc, isSelected: isSelected)
            if isSelected {
                tabMetadataBadges(for: doc)
            }
            tabCloseButton(for: doc)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(isSelected ? palette.accentColor.opacity(0.18) : palette.windowColor)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(isSelected ? palette.accentColor.opacity(0.6) : palette.borderColor, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            editorManager.activeDocumentID = doc.id
        }
        .contextMenu {
            Button("Close Tab") {
                Task { await editorManager.closeDocumentWithPrompt(id: doc.id) }
            }
            Button("Close Other Tabs") {
                Task {
                    for other in editorManager.documents where other.id != doc.id {
                        _ = await editorManager.closeDocumentWithPrompt(id: other.id)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func tabIndicators(for doc: EditorDocument) -> some View {
        if doc.isDirty {
            Circle()
                .fill(Color(hex: "#e5c07b"))
                .frame(width: 7, height: 7)
                .help("Unsaved changes")
        }
        if doc.isReadOnly {
            Image(systemName: "lock.fill")
                .font(.caption2)
                .foregroundStyle(palette.secondaryTextColor)
                .help("Read-only document")
        }
        if doc.isRemote {
            Image(systemName: "network")
                .font(.caption2)
                .foregroundStyle(palette.accentColor)
                .help("Remote server file")
        }
    }

    private func tabTitle(for doc: EditorDocument, isSelected: Bool) -> some View {
        Text(doc.title)
            .font(SparkleTheme.Typography.caption)
            .foregroundStyle(isSelected ? palette.primaryTextColor : palette.secondaryTextColor)
            .lineLimit(1)
    }

    private func tabMetadataBadges(for doc: EditorDocument) -> some View {
        HStack(spacing: 4) {
            Text(doc.lineEnding.displayName)
                .font(SparkleTheme.Typography.monoSmall)
                .foregroundStyle(palette.secondaryTextColor)
                .padding(.horizontal, 3)
                .padding(.vertical, 1)
                .background(palette.windowColor.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 3))

            Text(doc.encoding.rawValue)
                .font(SparkleTheme.Typography.monoSmall)
                .foregroundStyle(palette.secondaryTextColor)
                .padding(.horizontal, 3)
                .padding(.vertical, 1)
                .background(palette.windowColor.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 3))
        }
    }

    private func tabCloseButton(for doc: EditorDocument) -> some View {
        Button {
            Task { await editorManager.closeDocumentWithPrompt(id: doc.id) }
        } label: {
            Image(systemName: "xmark")
                .font(.caption2)
                .foregroundStyle(palette.secondaryTextColor)
        }
        .buttonStyle(.plain)
        .help("Close tab (⌘W)")
    }
}
