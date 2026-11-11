import SparkleCore
import SparkleDesignSystem
import SparkleTransferEngine
import SwiftUI

public enum TransferQueueFilter: String, CaseIterable, Identifiable {
    case active
    case completed
    case failed
    case all

    public var id: String {
        rawValue
    }

    func title(strings: AppStrings) -> String {
        switch self {
        case .active: return strings.t("transfers.filterActive")
        case .completed: return strings.t("transfers.filterCompleted")
        case .failed: return strings.t("transfers.filterFailed")
        case .all: return strings.t("transfers.filterAll")
        }
    }

    func matches(_ status: TransferStatus) -> Bool {
        switch self {
        case .active:
            return !status.isTerminal
        case .completed:
            return status == .completed
        case .failed:
            return status.isFailed || status == .cancelled
        case .all:
            return true
        }
    }
}

public struct TransferQueueView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var monitor: TransferMonitor
    @State private var selectedFilter: TransferQueueFilter = .all
    @State private var visibleLimit: Int = 150

    public init(appState: AppState) {
        self.appState = appState
        _monitor = ObservedObject(wrappedValue: appState.transferMonitor)
    }

    private var strings: AppStrings {
        appState.strings
    }

    private var palette: SparkleThemePalette {
        appState.activePalette
    }

    private var filteredSnapshots: [TransferSnapshot] {
        monitor.snapshots.filter { selectedFilter.matches($0.status) }
    }

    private var activeCount: Int {
        monitor.snapshots.count { !$0.status.isTerminal }
    }

    private var completedCount: Int {
        monitor.snapshots.count { $0.status == .completed }
    }

    private var failedCount: Int {
        monitor.snapshots.count { $0.status.isFailed || $0.status == .cancelled }
    }

    private var hasPausedOrInterrupted: Bool {
        monitor.snapshots.contains { $0.status == .paused || $0.status == .interrupted }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBar
            Divider().overlay(palette.borderColor)
            filterBar
            queueContent
        }
        .sparkleWorkspaceSurface(palette, useCanvas: true)
    }

    private var headerBar: some View {
        HStack(spacing: SparkleTheme.Spacing.small) {
            Label(strings.transfers, systemImage: "arrow.up.arrow.down.circle")
                .font(SparkleTheme.Typography.headline)

            conflictPolicyMenu

            Spacer()

            if appState.hasActiveConflictQueueRules {
                Button(strings.t("transfers.resetConflictRules")) {
                    Task { await appState.resetConflictQueueRules() }
                }
                .buttonStyle(.borderless)
                .font(SparkleTheme.Typography.caption)
                .foregroundStyle(palette.accentColor)
            }

            if activeCount > 0 {
                Button(strings.t("transfers.pauseAll")) {
                    Task { await appState.transferQueue.pauseAll() }
                }
                .buttonStyle(.borderless)
                .font(SparkleTheme.Typography.caption)

                Button(strings.t("transfers.abortAll"), role: .destructive) {
                    Task { await appState.transferQueue.cancelAll() }
                }
                .buttonStyle(.borderless)
                .font(SparkleTheme.Typography.caption)
                .foregroundStyle(SparkleTheme.Colors.danger)
            }

            if failedCount > 0 {
                Button(strings.t("transfers.retryAllFailed")) {
                    Task { await appState.transferQueue.retryAllFailed() }
                }
                .buttonStyle(.borderless)
                .font(SparkleTheme.Typography.caption)
                .foregroundStyle(palette.accentColor)
            } else if hasPausedOrInterrupted {
                Button(strings.t("transfers.resume")) {
                    Task { await appState.transferQueue.resumeAll() }
                }
                .buttonStyle(.borderless)
                .font(SparkleTheme.Typography.caption)
                .foregroundStyle(palette.accentColor)
            }

            clearMenu
        }
        .padding(.horizontal, SparkleTheme.Spacing.medium)
        .padding(.vertical, SparkleTheme.Spacing.tiny)
        .background(palette.windowColor)
    }

    @ViewBuilder
    private var clearMenu: some View {
        if completedCount > 0 || failedCount > 0 {
            Menu(strings.t("transfers.clearFinished")) {
                if completedCount > 0 {
                    Button("\(strings.t("transfers.clearCompleted")) (\(completedCount))") {
                        Task { await appState.transferQueue.clearCompleted() }
                    }
                }
                if failedCount > 0 {
                    Button("\(strings.t("transfers.clearFailed")) (\(failedCount))") {
                        Task { await appState.transferQueue.clearFailed() }
                    }
                }
                Divider()
                Button(strings.t("transfers.clearFinished")) {
                    Task { await appState.transferQueue.clearFinished() }
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .font(SparkleTheme.Typography.caption)
        }
    }

    private var conflictPolicyMenu: some View {
        let uploadTitle = "\(strings.t("transfers.uploadPolicy")): "
            + appState.defaultUploadConflictPolicy.localizedTitle(strings)
        let downloadTitle = "\(strings.t("transfers.downloadPolicy")): "
            + appState.defaultDownloadConflictPolicy.localizedTitle(strings)
        return Menu {
            Menu(uploadTitle) {
                ForEach(TransferConflictPolicy.allCases, id: \.self) { policy in
                    Button {
                        appState.defaultUploadConflictPolicy = policy
                        Task { await appState.applyConflictPolicySettings() }
                    } label: {
                        policyLabel(policy, selected: appState.defaultUploadConflictPolicy == policy)
                    }
                }
            }
            Menu(downloadTitle) {
                ForEach(TransferConflictPolicy.allCases, id: \.self) { policy in
                    Button {
                        appState.defaultDownloadConflictPolicy = policy
                        Task { await appState.applyConflictPolicySettings() }
                    } label: {
                        policyLabel(policy, selected: appState.defaultDownloadConflictPolicy == policy)
                    }
                }
            }
        } label: {
            Label(strings.t("transfers.action"), systemImage: "doc.on.doc")
                .font(SparkleTheme.Typography.caption)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    @ViewBuilder
    private func policyLabel(_ policy: TransferConflictPolicy, selected: Bool) -> some View {
        if selected {
            Label(policy.localizedTitle(strings), systemImage: "checkmark")
        } else {
            Text(policy.localizedTitle(strings))
        }
    }

    private var filterBar: some View {
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

    private func countForFilter(_ filter: TransferQueueFilter) -> Int {
        switch filter {
        case .active: return activeCount
        case .completed: return completedCount
        case .failed: return failedCount
        case .all: return monitor.snapshots.count
        }
    }

    @ViewBuilder
    private var queueContent: some View {
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
