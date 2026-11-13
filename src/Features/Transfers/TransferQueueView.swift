import SparkleCore
import SparkleDesignSystem
import SparkleTransferEngine
import SwiftUI

public enum TransferQueueFilter: String, CaseIterable, Identifiable {
    case queued
    case failed
    case successful

    public var id: String {
        rawValue
    }

    func title(strings: AppStrings) -> String {
        switch self {
        case .queued: return strings.t("transfers.queuedFiles")
        case .failed: return strings.t("transfers.failedTransfers")
        case .successful: return strings.t("transfers.successfulTransfers")
        }
    }

    func matches(_ status: TransferStatus) -> Bool {
        switch self {
        case .queued:
            return !status.isTerminal
        case .failed:
            return status.isFailed || status == .cancelled
        case .successful:
            return status == .completed
        }
    }

    public static var active: TransferQueueFilter {
        .queued
    }

    public static var completed: TransferQueueFilter {
        .successful
    }

    public static var all: TransferQueueFilter {
        .queued
    }
}

public struct TransferQueueView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var monitor: TransferMonitor
    @State var selectedFilter: TransferQueueFilter = .queued
    @State var visibleLimit: Int = 150

    public init(appState: AppState) {
        self.appState = appState
        _monitor = ObservedObject(wrappedValue: appState.transferMonitor)
    }

    var strings: AppStrings {
        appState.strings
    }

    var palette: SparkleThemePalette {
        appState.activePalette
    }

    var filteredSnapshots: [TransferSnapshot] {
        monitor.snapshots.filter { selectedFilter.matches($0.status) }
    }

    var activeCount: Int {
        monitor.snapshots.count { !$0.status.isTerminal }
    }

    var completedCount: Int {
        monitor.snapshots.count { $0.status == .completed }
    }

    var failedCount: Int {
        monitor.snapshots.count { $0.status.isFailed || $0.status == .cancelled }
    }

    private var hasPausedOrInterrupted: Bool {
        monitor.snapshots.contains { $0.status == .paused || $0.status == .interrupted }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBar
            Divider().overlay(palette.borderColor)
            tableHeader
            Divider().overlay(palette.borderColor)
            queueContent
            Divider().overlay(palette.borderColor)
            bottomTabBar
        }
        .sparkleWorkspaceSurface(palette, useCanvas: true)
    }

    private var headerBar: some View {
        HStack(spacing: SparkleTheme.Spacing.small) {
            Label(strings.transfers, systemImage: "arrow.up.arrow.down.circle")
                .font(SparkleTheme.Typography.headline)

            conflictPolicyMenu

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    appState.isTransferDrawerVisible = false
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                    Text(strings.t("transfers.hideMinimize"))
                        .font(SparkleTheme.Typography.caption)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(palette.windowColor)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(palette.borderColor.opacity(0.6), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .help(strings.t("transfers.hideMinimizeTooltip"))

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
}
