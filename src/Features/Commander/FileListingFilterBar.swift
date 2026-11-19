import AppKit
import SparkleDesignSystem
import SwiftUI

/// Preset quick filter definition for file listings.
struct FilterPreset: Identifiable, Equatable {
    let id: String
    let label: String
    let pattern: String
}

/// Real-time file listing filter bar supporting substrings, extensions (*.ext), and hidden files (.*).
public struct FileListingFilterBar: View {
    @Binding var query: String
    @Binding var isPresented: Bool
    let totalCount: Int
    let filteredCount: Int
    let palette: SparkleThemePalette
    let onQueryChanged: (String) -> Void

    private let presets: [FilterPreset] = [
        FilterPreset(id: "all", label: "All", pattern: ""),
        FilterPreset(id: "hidden", label: "Hidden", pattern: ".*"),
        FilterPreset(id: "configs", label: "Configs", pattern: "*.conf"),
        FilterPreset(id: "logs", label: "Logs", pattern: "*.log"),
        FilterPreset(id: "source", label: "Source", pattern: "*.swift")
    ]

    public init(
        query: Binding<String>,
        isPresented: Binding<Bool>,
        totalCount: Int,
        filteredCount: Int,
        palette: SparkleThemePalette,
        onQueryChanged: @escaping (String) -> Void
    ) {
        self._query = query
        self._isPresented = isPresented
        self.totalCount = totalCount
        self.filteredCount = filteredCount
        self.palette = palette
        self.onQueryChanged = onQueryChanged
    }

    public var body: some View {
        HStack(spacing: SparkleTheme.Spacing.tiny) {
            searchFieldGroup
            presetPillsGroup
            Spacer(minLength: 0)
            statusBadgeAndDismiss
        }
        .padding(.horizontal, SparkleTheme.Spacing.small)
        .padding(.vertical, 4)
        .background(palette.windowColor.opacity(0.95))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(palette.borderColor.opacity(0.4)),
            alignment: .bottom
        )
    }

    private var searchFieldGroup: some View {
        HStack(spacing: 4) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .foregroundStyle(query.isEmpty ? palette.secondaryTextColor : palette.accentColor)
                .font(.system(size: 12))

            TextField("Filter files (e.g. *.log, hidden, search)...", text: $query)
                .textFieldStyle(.plain)
                .font(SparkleTheme.Typography.monoSmall)
                .onChange(of: query) { newValue in
                    onQueryChanged(newValue)
                }

            if !query.isEmpty {
                Button {
                    query = ""
                    onQueryChanged("")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(palette.secondaryTextColor)
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .help("Clear filter")
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(palette.canvasColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(query.isEmpty ? palette.borderColor.opacity(0.5) : palette.accentColor, lineWidth: 1)
        )
        .frame(minWidth: 160, maxWidth: 280)
    }

    private var presetPillsGroup: some View {
        HStack(spacing: 3) {
            ForEach(presets) { preset in
                let isActive = query == preset.pattern
                Button {
                    query = preset.pattern
                    onQueryChanged(preset.pattern)
                } label: {
                    Text(preset.label)
                        .font(.system(size: 10, weight: isActive ? .semibold : .regular))
                        .foregroundStyle(isActive ? palette.accentColor : palette.secondaryTextColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(isActive ? palette.accentColor.opacity(0.15) : Color.clear)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var statusBadgeAndDismiss: some View {
        HStack(spacing: 6) {
            if !query.isEmpty {
                Text("\(filteredCount) / \(totalCount)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.secondaryTextColor)
            }

            Button {
                query = ""
                onQueryChanged("")
                isPresented = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
                    .foregroundStyle(palette.secondaryTextColor)
            }
            .buttonStyle(.plain)
            .help("Close filter bar (Esc)")
        }
    }
}
