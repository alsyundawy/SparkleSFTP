import SparkleCore
import SparkleDesignSystem
import SparkleTransferEngine
import SwiftUI

extension TransferQueueView {
    @ViewBuilder
    func policyLabel(_ policy: TransferConflictPolicy, selected: Bool) -> some View {
        if selected {
            Label(policy.localizedTitle(strings), systemImage: "checkmark")
        } else {
            Text(policy.localizedTitle(strings))
        }
    }

    var tableHeader: some View {
        HStack(spacing: 0) {
            switch selectedFilter {
            case .queued:
                headerCell(
                    strings.t("transfers.colLocalFile"),
                    minWidth: 160,
                    maxWidth: .infinity,
                    alignment: .leading
                )
                headerDivider
                headerCell(strings.t("transfers.colDirection"), width: 65, alignment: .center)
                headerDivider
                headerCell(
                    strings.t("transfers.colRemoteFile"),
                    minWidth: 160,
                    maxWidth: .infinity,
                    alignment: .leading
                )
                headerDivider
                headerCell(strings.t("transfers.colSize"), width: 85, alignment: .trailing)
                headerDivider
                headerCell(strings.t("transfers.colPriority"), width: 65, alignment: .center)
                headerDivider
                headerCell(strings.t("transfers.colStatus"), width: 180, alignment: .leading)
            case .failed:
                headerCell(
                    strings.t("transfers.colLocalFile"),
                    minWidth: 150,
                    maxWidth: .infinity,
                    alignment: .leading
                )
                headerDivider
                headerCell(strings.t("transfers.colDirection"), width: 65, alignment: .center)
                headerDivider
                headerCell(
                    strings.t("transfers.colRemoteFile"),
                    minWidth: 150,
                    maxWidth: .infinity,
                    alignment: .leading
                )
                headerDivider
                headerCell(strings.t("transfers.colSize"), width: 85, alignment: .trailing)
                headerDivider
                headerCell(strings.t("transfers.colPriority"), width: 65, alignment: .center)
                headerDivider
                headerCell(strings.t("transfers.colTime"), width: 75, alignment: .center)
                headerDivider
                headerCell(
                    strings.t("transfers.colReason"),
                    minWidth: 150,
                    maxWidth: .infinity,
                    alignment: .leading
                )
            case .successful:
                headerCell(
                    strings.t("transfers.colLocalFile"),
                    minWidth: 180,
                    maxWidth: .infinity,
                    alignment: .leading
                )
                headerDivider
                headerCell(strings.t("transfers.colDirection"), width: 65, alignment: .center)
                headerDivider
                headerCell(
                    strings.t("transfers.colRemoteFile"),
                    minWidth: 180,
                    maxWidth: .infinity,
                    alignment: .leading
                )
                headerDivider
                headerCell(strings.t("transfers.colSize"), width: 85, alignment: .trailing)
                headerDivider
                headerCell(strings.t("transfers.colPriority"), width: 65, alignment: .center)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(palette.windowColor.opacity(0.85))
    }

    @ViewBuilder
    private func headerCell(
        _ title: String,
        width: CGFloat? = nil,
        minWidth: CGFloat? = nil,
        maxWidth: CGFloat? = nil,
        alignment: Alignment = .leading
    ) -> some View {
        if let width {
            Text(title)
                .font(SparkleTheme.Typography.caption.weight(.semibold))
                .foregroundStyle(palette.secondaryTextColor)
                .lineLimit(1)
                .frame(width: width, alignment: alignment)
                .padding(.horizontal, 4)
        } else {
            Text(title)
                .font(SparkleTheme.Typography.caption.weight(.semibold))
                .foregroundStyle(palette.secondaryTextColor)
                .lineLimit(1)
                .frame(minWidth: minWidth, maxWidth: maxWidth, alignment: alignment)
                .padding(.horizontal, 4)
        }
    }

    private var headerDivider: some View {
        Rectangle()
            .fill(palette.borderColor.opacity(0.35))
            .frame(width: 1, height: 14)
    }

    var bottomTabBar: some View {
        HStack(spacing: 0) {
            ForEach(TransferQueueFilter.allCases, id: \.id) { filter in
                let count = countForFilter(filter)
                let isSelected = selectedFilter == filter
                Button {
                    selectedFilter = filter
                    visibleLimit = 150
                } label: {
                    HStack(spacing: 4) {
                        Text(filter.title(strings: strings))
                            .fontWeight(isSelected ? .bold : .regular)
                        if count > 0 {
                            Text("(\(count))")
                                .font(SparkleTheme.Typography.caption)
                                .foregroundStyle(isSelected ? palette.accentColor : palette.secondaryTextColor)
                        }
                    }
                    .font(SparkleTheme.Typography.caption)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5)
                    .background(isSelected ? palette.canvasColor : palette.windowColor)
                    .foregroundStyle(isSelected ? palette.primaryTextColor : palette.secondaryTextColor)
                    .overlay(
                        Rectangle()
                            .frame(height: 2)
                            .foregroundColor(isSelected ? palette.accentColor : Color.clear),
                        alignment: .top
                    )
                    .overlay(
                        Rectangle()
                            .stroke(palette.borderColor.opacity(0.4), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Text("\(monitor.snapshots.count) \(strings.t("transfers.items"))")
                .font(SparkleTheme.Typography.caption)
                .foregroundStyle(palette.secondaryTextColor)
                .padding(.trailing, SparkleTheme.Spacing.small)
        }
        .background(palette.windowColor)
    }

    func countForFilter(_ filter: TransferQueueFilter) -> Int {
        switch filter {
        case .queued: return activeCount
        case .failed: return failedCount
        case .successful: return completedCount
        }
    }

    @ViewBuilder
    var queueContent: some View {
        let items = filteredSnapshots
        if items.isEmpty {
            Text(strings.t("transfers.noTransfers"))
                .font(SparkleTheme.Typography.caption)
                .foregroundStyle(palette.secondaryTextColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
                .background(palette.canvasColor)
        } else {
            let sliced = Array(items.prefix(visibleLimit))
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(sliced.enumerated()), id: \.element.id) { index, snapshot in
                        TransferQueueRowView(
                            snapshot: snapshot,
                            filter: selectedFilter,
                            palette: palette,
                            strings: strings,
                            onPause: { Task { await appState.transferQueue.pause(id: snapshot.id) } },
                            onRetry: { Task { await appState.transferQueue.retry(id: snapshot.id) } },
                            onCancel: { Task { await appState.transferQueue.cancel(id: snapshot.id) } }
                        )
                        .background(index % 2 == 0 ? palette.canvasColor : palette.windowColor.opacity(0.3))
                        Divider().overlay(palette.borderColor.opacity(0.2))
                    }
                    if items.count > sliced.count {
                        HStack {
                            Spacer()
                            Button("\(strings.t("transfers.showMore")) (+\(items.count - sliced.count))") {
                                visibleLimit += 150
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .padding(.vertical, 4)
                            Spacer()
                        }
                    }
                }
            }
            .background(palette.canvasColor)
        }
    }
}
