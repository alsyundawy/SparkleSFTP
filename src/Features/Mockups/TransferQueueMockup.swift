import AppKit
import SparkleCore
import SparkleDesignSystem
import SwiftUI

/// High-fidelity Transfer Queue mockup displaying batch transfers, speeds, ETAs, and conflict badges.
public struct TransferQueueMockup: View {
    @State private var selectedFilter: String = "All"
    @State private var selectedTransferID: UUID? = MockData.mockTransfers.first?.id

    @Environment(\.sparklePalette) private var palette

    private let filterOptions = ["All", "Active", "Completed", "Conflict", "Queued"]

    public init() {}

    private var filteredTransfers: [MockTransferItem] {
        switch selectedFilter {
        case "Active":
            return MockData.mockTransfers.filter { $0.status == .active }
        case "Completed":
            return MockData.mockTransfers.filter { $0.status == .completed }
        case "Conflict":
            return MockData.mockTransfers.filter { $0.status == .conflict }
        case "Queued":
            return MockData.mockTransfers.filter { $0.status == .queued }
        default:
            return MockData.mockTransfers
        }
    }

    public var body: some View {
        let tokens = SparkleSemanticTokens(palette: palette)

        VStack(spacing: 0) {
            // MARK: - Top Metrics & Filter Header

            headerToolbar(tokens: tokens)

            Divider().overlay(tokens.hairlineBorder)

            // MARK: - Transfer Queue List Card

            VStack(spacing: 0) {
                // Column Headers
                HStack(spacing: 12) {
                    Text("Transfer Job")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Progress")
                        .frame(width: 180, alignment: .leading)
                    Text("Speed / ETA")
                        .frame(width: 130, alignment: .trailing)
                    Text("Status")
                        .frame(width: 100, alignment: .trailing)
                    Text("Actions")
                        .frame(width: 80, alignment: .trailing)
                }
                .font(SparkleSemanticTokens.captionSemiboldFont)
                .foregroundStyle(tokens.secondaryText)
                .padding(.horizontal, SparkleSemanticTokens.spacingLg)
                .padding(.vertical, 8)
                .background(tokens.elevatedHeaderBackground)

                Divider().overlay(tokens.hairlineBorder)

                // Queue Rows
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filteredTransfers) { item in
                            transferRowView(item: item, tokens: tokens)
                        }
                    }
                    .padding(SparkleSemanticTokens.spacingSm)
                }
            }
            .sparkleCardStyle(tokens: tokens)
            .padding(SparkleSemanticTokens.spacingMd)

            Spacer(minLength: 0)

            // MARK: - Bottom Action Bar

            bottomActionBar(tokens: tokens)
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(tokens.windowBackground)
    }

    // MARK: - Header Toolbar

    private func headerToolbar(tokens: SparkleSemanticTokens) -> some View {
        HStack(spacing: 16) {
            filterSegmentedTabs(tokens: tokens)

            Spacer()

            // Summary Speed & Active Metrics
            HStack(spacing: 16) {
                metricBadge(
                    icon: "speedometer",
                    label: "Aggregate Speed",
                    value: "24.2 MB/s",
                    tint: .blue,
                    tokens: tokens
                )
                metricBadge(
                    icon: "arrow.up.arrow.down",
                    label: "Active Jobs",
                    value: "2 / 5",
                    tint: .green,
                    tokens: tokens
                )
                metricBadge(
                    icon: "exclamationmark.triangle.fill",
                    label: "Conflicts",
                    value: "1",
                    tint: .purple,
                    tokens: tokens
                )
            }
        }
        .padding(.horizontal, SparkleSemanticTokens.spacingMd)
        .padding(.vertical, SparkleSemanticTokens.spacingSm)
        .background(tokens.elevatedHeaderBackground)
    }

    private func filterSegmentedTabs(tokens: SparkleSemanticTokens) -> some View {
        HStack(spacing: 4) {
            ForEach(filterOptions, id: \.self) { option in
                let isSelected = (selectedFilter == option)
                let font = isSelected ? SparkleSemanticTokens.captionSemiboldFont
                    : SparkleSemanticTokens.captionFont

                Button {
                    selectedFilter = option
                } label: {
                    Text(option)
                        .font(font)
                        .foregroundStyle(isSelected ? tokens.accent : tokens.secondaryText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isSelected ? tokens.rowSelectionBackground : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(tokens.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(tokens.hairlineBorder, lineWidth: 1))
    }

    private func metricBadge(
        icon: String,
        label: String,
        value: String,
        tint: Color,
        tokens: SparkleSemanticTokens
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .sparkleIconContainer(tint: tint)

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(tokens.tertiaryText)
                Text(value)
                    .font(SparkleSemanticTokens.monoBoldFont)
                    .foregroundStyle(tokens.primaryText)
            }
        }
    }

    // MARK: - Transfer Row View

    private func transferRowView(item: MockTransferItem, tokens: SparkleSemanticTokens) -> some View {
        MockTransferQueueRowView(
            item: item,
            isSelected: selectedTransferID == item.id,
            tokens: tokens,
            onSelect: { selectedTransferID = item.id }
        )
    }

    // MARK: - Bottom Action Bar

    private func bottomActionBar(tokens: SparkleSemanticTokens) -> some View {
        HStack(spacing: 12) {
            Button {} label: {
                Label("Pause All", systemImage: "pause.circle")
            }
            .buttonStyle(.bordered)

            Button {} label: {
                Label("Resume All", systemImage: "play.circle")
            }
            .buttonStyle(.bordered)

            Button {} label: {
                Label("Clear Completed", systemImage: "checkmark.circle")
            }
            .buttonStyle(.bordered)

            Spacer()

            Button(role: .destructive) {} label: {
                Label("Cancel All Transfers", systemImage: "xmark.octagon.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .padding(.horizontal, SparkleSemanticTokens.spacingMd)
        .padding(.vertical, SparkleSemanticTokens.spacingSm)
        .background(tokens.elevatedHeaderBackground)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(tokens.hairlineBorder),
            alignment: .top
        )
    }
}

// MARK: - Transfer Queue Row View

private struct MockTransferQueueRowView: View {
    let item: MockTransferItem
    let isSelected: Bool
    let tokens: SparkleSemanticTokens
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                transferFileInfo(item: item, tokens: tokens)
                transferProgressSection(item: item, tokens: tokens)
                transferSpeedSection(item: item, tokens: tokens)

                StatusBadge(
                    title: item.status.rawValue,
                    iconName: item.status.iconName,
                    tint: item.status.badgeTint
                )
                .frame(width: 100, alignment: .trailing)

                transferRowActions(item: item)
            }
            .padding(.horizontal, SparkleSemanticTokens.spacingSm)
            .frame(minHeight: SparkleSemanticTokens.dataRowHeight + 10)
            .background(
                RoundedRectangle(cornerRadius: SparkleSemanticTokens.rowCornerRadius, style: .continuous)
                    .fill(isSelected ? tokens.rowSelectionBackground : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private func transferFileInfo(item: MockTransferItem, tokens: SparkleSemanticTokens) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.direction.iconName)
                .font(.system(size: 12))
                .sparkleIconContainer(tint: item.direction == .upload ? .indigo : .blue)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.filename)
                        .font(SparkleSemanticTokens.bodyFont)
                        .foregroundStyle(tokens.primaryText)
                        .lineLimit(1)

                    Text("(\(item.formattedTotalSize))")
                        .font(SparkleSemanticTokens.monoFont)
                        .foregroundStyle(tokens.tertiaryText)
                }

                Text("\(item.sourcePath) → \(item.destinationPath)")
                    .font(SparkleSemanticTokens.monoFont)
                    .foregroundStyle(tokens.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func transferProgressSection(item: MockTransferItem, tokens: SparkleSemanticTokens) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(Int(item.fraction * 100))%")
                    .font(SparkleSemanticTokens.monoBoldFont)
                    .foregroundStyle(tokens.primaryText)
                Spacer()
                Text(item.direction.rawValue)
                    .font(.system(size: 10))
                    .foregroundStyle(tokens.tertiaryText)
            }

            ModernProgressBar(
                fraction: item.fraction,
                tint: item.status.badgeTint,
                trackTint: tokens.hairlineBorder
            )
        }
        .frame(width: 180)
    }

    private func transferSpeedSection(item: MockTransferItem, tokens: SparkleSemanticTokens) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(item.speedMBs > 0 ? item.formattedSpeed : "-")
                .font(SparkleSemanticTokens.monoBoldFont)
                .foregroundStyle(item.speedMBs > 0 ? tokens.primaryText : tokens.tertiaryText)

            Text(item.etaString)
                .font(SparkleSemanticTokens.monoFont)
                .foregroundStyle(tokens.secondaryText)
        }
        .frame(width: 130, alignment: .trailing)
    }

    private func transferRowActions(item: MockTransferItem) -> some View {
        HStack(spacing: 6) {
            if item.status == .conflict {
                Button {} label: {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .tint(.purple)
            } else if item.status == .active {
                Button {} label: {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
            } else if item.status == .paused || item.status == .queued {
                Button {} label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
            }

            Button {} label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
        .frame(width: 80, alignment: .trailing)
    }
}

// MARK: - Xcode Previews (1280×800)

#if DEBUG
    struct TransferQueueMockup_Previews: PreviewProvider {
        @MainActor
        static var previews: some View {
            Group {
                TransferQueueMockup()
                    .environment(\.sparklePalette, SparkleThemeCatalog.defaultDark)
                    .preferredColorScheme(.dark)
                    .previewDisplayName("Transfer Queue Dark (1280×800)")

                TransferQueueMockup()
                    .environment(\.sparklePalette, SparkleThemeCatalog.defaultLight)
                    .preferredColorScheme(.light)
                    .previewDisplayName("Transfer Queue Light (1280×800)")
            }
            .frame(width: 1280, height: 800)
        }
    }
#endif
