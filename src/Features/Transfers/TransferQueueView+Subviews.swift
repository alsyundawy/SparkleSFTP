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

    var filterBar: some View {
        HStack(spacing: SparkleTheme.Spacing.tiny) {
            ForEach(TransferQueueFilter.allCases) { filter in
                let count = countForFilter(filter)
                Button {
                    selectedFilter = filter
                    visibleLimit = 150
                } label: {
                    Text("\(filter.title(strings: strings)) (\(count))")
                        .font(SparkleTheme.Typography.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            selectedFilter == filter ? palette.accentColor.opacity(0.22) : Color.clear,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
                .foregroundStyle(selectedFilter == filter ? palette.accentColor : palette.secondaryTextColor)
            }
            Spacer()
            Text("\(monitor.snapshots.count) \(strings.t("transfers.items"))")
                .font(SparkleTheme.Typography.caption)
                .foregroundStyle(palette.secondaryTextColor)
        }
        .padding(.horizontal, SparkleTheme.Spacing.medium)
        .padding(.vertical, 4)
        .background(palette.windowColor.opacity(0.65))
    }

    func countForFilter(_ filter: TransferQueueFilter) -> Int {
        switch filter {
        case .active: return activeCount
        case .completed: return completedCount
        case .failed: return failedCount
        case .all: return monitor.snapshots.count
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
            List {
                ForEach(sliced) { snapshot in
                    TransferQueueRowView(
                        snapshot: snapshot,
                        palette: palette,
                        strings: strings,
                        onPause: { Task { await appState.transferQueue.pause(id: snapshot.id) } },
                        onRetry: { Task { await appState.transferQueue.retry(id: snapshot.id) } },
                        onCancel: { Task { await appState.transferQueue.cancel(id: snapshot.id) } }
                    )
                    .listRowBackground(palette.canvasColor)
                }
                if items.count > sliced.count {
                    HStack {
                        Spacer()
                        Button("\(strings.t("transfers.showMore")) (+\(items.count - sliced.count))") {
                            visibleLimit += 150
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        Spacer()
                    }
                    .listRowBackground(palette.canvasColor)
                }
            }
            .scrollContentBackground(.hidden)
            .background(palette.canvasColor)
        }
    }
}
