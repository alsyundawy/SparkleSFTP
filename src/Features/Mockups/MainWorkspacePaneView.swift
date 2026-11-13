import AppKit
import SparkleCore
import SparkleDesignSystem
import SwiftUI

/// Configuration for a Commander file listing pane.
public struct FilePaneConfig: Sendable {
    public let title: String
    public let iconName: String
    public let path: String
    public let diskSpace: MockDiskSpace
    public let items: [MockFileItem]

    public init(
        title: String,
        iconName: String,
        path: String,
        diskSpace: MockDiskSpace,
        items: [MockFileItem]
    ) {
        self.title = title
        self.iconName = iconName
        self.path = path
        self.diskSpace = diskSpace
        self.items = items
    }
}

/// Dual-pane commander file listing view.
public struct MainWorkspacePaneView: View {
    public let config: FilePaneConfig
    @Binding public var selectedID: String?
    public let tokens: SparkleSemanticTokens

    public init(
        config: FilePaneConfig,
        selectedID: Binding<String?>,
        tokens: SparkleSemanticTokens
    ) {
        self.config = config
        _selectedID = selectedID
        self.tokens = tokens
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerView
            PathBreadcrumbsBar(path: config.path)
                .padding(.horizontal, SparkleSemanticTokens.spacingSm)
                .padding(.bottom, 6)
            DiskSpaceBar(diskSpace: config.diskSpace)
                .padding(.horizontal, SparkleSemanticTokens.spacingSm)
                .padding(.bottom, 6)
            columnHeaderView
            Divider().overlay(tokens.hairlineBorder)
            rowsScrollView
        }
        .sparkleCardStyle(tokens: tokens)
    }

    private var headerView: some View {
        HStack(spacing: 8) {
            Image(systemName: config.iconName)
                .font(.system(size: 13, weight: .medium))
                .sparkleIconContainer(tint: tokens.accent)

            Text(config.title)
                .font(SparkleSemanticTokens.titleFont)
                .foregroundStyle(tokens.primaryText)

            Spacer()

            Text("\(config.items.count) items")
                .font(SparkleSemanticTokens.captionFont)
                .foregroundStyle(tokens.secondaryText)
        }
        .padding(.horizontal, SparkleSemanticTokens.spacingSm)
        .padding(.vertical, 6)
    }

    private var columnHeaderView: some View {
        HStack {
            Text("Name")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Size")
                .frame(width: 75, alignment: .trailing)
            Text("Permissions")
                .frame(width: 90, alignment: .leading)
            Text("Modified")
                .frame(width: 120, alignment: .trailing)
        }
        .font(SparkleSemanticTokens.captionSemiboldFont)
        .foregroundStyle(tokens.secondaryText)
        .padding(.horizontal, SparkleSemanticTokens.spacingSm)
        .padding(.vertical, 4)
        .background(tokens.elevatedHeaderBackground)
    }

    private var rowsScrollView: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(config.items) { item in
                    rowButton(for: item)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func rowButton(for item: MockFileItem) -> some View {
        let isSelected = (selectedID == item.id)
        return Button {
            selectedID = item.id
        } label: {
            HStack(spacing: 8) {
                Image(systemName: item.iconName)
                    .font(.system(size: 11))
                    .sparkleIconContainer(tint: item.iconTint)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(SparkleSemanticTokens.bodyFont)
                        .foregroundStyle(isSelected ? tokens.accent : tokens.primaryText)
                        .lineLimit(1)
                    Text(item.isDirectory ? "Directory" : (item.isSymlink ? "Symbolic Link" : "File"))
                        .font(SparkleSemanticTokens.titleSecondaryFont)
                        .foregroundStyle(tokens.tertiaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(item.formattedSize)
                    .font(SparkleSemanticTokens.monoFont)
                    .foregroundStyle(tokens.secondaryText)
                    .frame(width: 75, alignment: .trailing)

                Text(item.permissions)
                    .font(SparkleSemanticTokens.monoFont)
                    .foregroundStyle(tokens.tertiaryText)
                    .frame(width: 90, alignment: .leading)

                Text(item.modifiedAt)
                    .font(SparkleSemanticTokens.monoFont)
                    .foregroundStyle(tokens.secondaryText)
                    .frame(width: 120, alignment: .trailing)
            }
            .padding(.horizontal, SparkleSemanticTokens.spacingSm)
            .frame(height: SparkleSemanticTokens.dataRowHeight)
            .background(
                RoundedRectangle(cornerRadius: SparkleSemanticTokens.rowCornerRadius, style: .continuous)
                    .fill(isSelected ? tokens.rowSelectionBackground : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}
