import SparkleCore
import SparkleDesignSystem
import SparkleTransferEngine
import SwiftUI

public struct TransferQueueView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var monitor: TransferMonitor

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    public init(appState: AppState) {
        self.appState = appState
        _monitor = ObservedObject(wrappedValue: appState.transferMonitor)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(appState.strings.transfers, systemImage: "arrow.up.arrow.down.circle")
                    .font(SparkleTheme.Typography.headline)
                Spacer()
                Text("\(monitor.snapshots.count) \(appState.strings.t("transfers.items"))")
                    .font(SparkleTheme.Typography.caption)
                    .foregroundStyle(appState.activePalette.secondaryTextColor)
                if monitor.snapshots.contains(where: \.status.isTerminal) {
                    Button(appState.strings.t("transfers.clearFinished")) {
                        Task { await appState.transferQueue.clearFinished() }
                    }
                    .buttonStyle(.borderless)
                    .font(SparkleTheme.Typography.caption)
                }
            }
            .padding(.horizontal, SparkleTheme.Spacing.medium)
            .padding(.vertical, SparkleTheme.Spacing.tiny)
            .background(appState.activePalette.windowColor)

            if monitor.snapshots.isEmpty {
                Text(appState.strings.t("transfers.noTransfers"))
                    .font(SparkleTheme.Typography.caption)
                    .foregroundStyle(appState.activePalette.secondaryTextColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                    .background(appState.activePalette.canvasColor)
            } else {
                List(monitor.snapshots) { snapshot in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(
                                systemName: snapshot.metadata.direction == .upload
                                    ? SparkleTheme.Symbols.upload
                                    : SparkleTheme.Symbols.download
                            )
                            Text(snapshot.metadata.destination.displayPath)
                                .font(SparkleTheme.Typography.body)
                                .lineLimit(1)
                            Spacer()
                            StatusPill(
                                title: snapshot.status.statusCode,
                                systemImage: "circle.fill",
                                tint: statusTint(snapshot.status)
                            )

                            if snapshot.status.isActive || snapshot.status == .queued {
                                Button {
                                    Task { await appState.transferQueue.pause(id: snapshot.id) }
                                } label: {
                                    Image(systemName: "pause.circle")
                                }
                                .buttonStyle(.borderless)
                                Button {
                                    Task { await appState.transferQueue.cancel(id: snapshot.id) }
                                } label: {
                                    Image(systemName: "xmark.circle")
                                }
                                .buttonStyle(.borderless)
                            } else if snapshot.status == .paused || snapshot.status == .interrupted {
                                Button {
                                    Task { await appState.transferQueue.retry(id: snapshot.id) }
                                } label: {
                                    Image(systemName: "play.circle")
                                }
                                .buttonStyle(.borderless)
                                Button {
                                    Task { await appState.transferQueue.cancel(id: snapshot.id) }
                                } label: {
                                    Image(systemName: "xmark.circle")
                                }
                                .buttonStyle(.borderless)
                            } else if case .failed = snapshot.status {
                                Button {
                                    Task { await appState.transferQueue.retry(id: snapshot.id) }
                                } label: {
                                    Image(systemName: "arrow.clockwise.circle")
                                }
                                .buttonStyle(.borderless)
                            } else if snapshot.status == .cancelled {
                                Button {
                                    Task { await appState.transferQueue.retry(id: snapshot.id) }
                                } label: {
                                    Image(systemName: "arrow.clockwise.circle")
                                }
                                .buttonStyle(.borderless)
                            }
                        }

                        if case let .failed(error) = snapshot.status {
                            Text(error.errorDescription ?? appState.strings.t("transfers.transferFailed"))
                                .font(SparkleTheme.Typography.caption)
                                .foregroundStyle(SparkleTheme.Colors.danger)
                                .lineLimit(2)
                        }

                        TransferProgressBar(fraction: snapshot.progress.percentage, tint: statusTint(snapshot.status))

                        HStack {
                            let done = Self.byteFormatter.string(fromByteCount: snapshot.progress.bytesTransferred)
                            let total = Self.byteFormatter.string(fromByteCount: snapshot.progress.totalBytes)
                            Text("\(done) / \(total)")
                            Spacer()
                            if snapshot.progress.bytesPerSecond > 0 {
                                let rate = Self.byteFormatter.string(fromByteCount: snapshot.progress.bytesPerSecond)
                                Text("\(rate)/s")
                            }
                        }
                        .font(SparkleTheme.Typography.caption)
                        .foregroundStyle(appState.activePalette.secondaryTextColor)
                    }
                    .padding(.vertical, 2)
                    .listRowBackground(appState.activePalette.canvasColor)
                }
                .scrollContentBackground(.hidden)
                .background(appState.activePalette.canvasColor)
            }
        }
        .sparkleWorkspaceSurface(appState.activePalette, useCanvas: true)
    }

    private func statusTint(_ status: TransferStatus) -> Color {
        switch status {
        case .completed: return SparkleTheme.Colors.success
        case .failed, .cancelled: return SparkleTheme.Colors.danger
        case .paused, .interrupted, .needsReview: return SparkleTheme.Colors.warning
        default: return SparkleTheme.Colors.accent
        }
    }
}

public struct ConflictResolutionSheet: View {
    @ObservedObject var appState: AppState
    let conflict: ConflictContext
    @State private var customName = ""

    public init(appState: AppState, conflict: ConflictContext) {
        self.appState = appState
        self.conflict = conflict
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SparkleTheme.Spacing.medium) {
            Text(appState.strings.t("transfers.fileAlreadyExists")).font(SparkleTheme.Typography.title)
            Text(conflict.destinationDisplayPath)
                .font(SparkleTheme.Typography.monoSmall)
            Text(
                "\(appState.strings.t("transfers.existingSize")): \(conflict.existingSize) bytes · "
                    + "\(appState.strings.t("transfers.incomingSize")): \(conflict.incomingSize) bytes"
            )
            .font(SparkleTheme.Typography.caption)

            TextField(appState.strings.t("transfers.optionalRename"), text: $customName)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button(appState.strings.t("common.skip")) { appState.resolveConflict(.skip) }
                Button(appState.strings.t("common.rename")) {
                    let existingName = URL(fileURLWithPath: conflict.destinationDisplayPath).lastPathComponent
                    let chosen = customName.isEmpty
                        ? ConflictResolver.uniqueName(from: existingName)
                        : customName
                    appState.resolveConflict(.rename(newFilename: chosen))
                }
                Spacer()
                Button(appState.strings.t("transfers.overwrite"), role: .destructive) {
                    appState.resolveConflict(.overwrite)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(SparkleTheme.Spacing.large)
        .frame(width: 440)
        .sparkleWorkspaceSurface(appState.activePalette)
    }
}
