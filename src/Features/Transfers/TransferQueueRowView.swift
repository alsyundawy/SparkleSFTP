import SparkleCore
import SparkleDesignSystem
import SwiftUI

extension TransferConflictPolicy {
    func localizedTitle(_ strings: AppStrings) -> String {
        switch self {
        case .ask: return strings.t("prefs.conflictAsk")
        case .overwrite: return strings.t("prefs.conflictOverwrite")
        case .overwriteIfNewer: return strings.t("prefs.conflictOverwriteIfNewer")
        case .overwriteIfDifferentSize: return strings.t("prefs.conflictOverwriteIfDiffSize")
        case .overwriteIfDifferentSizeOrNewer: return strings.t("prefs.conflictOverwriteIfDiffOrNewer")
        case .resume: return strings.t("prefs.conflictResume")
        case .rename: return strings.t("prefs.conflictRename")
        case .skip: return strings.t("prefs.conflictSkip")
        }
    }
}

struct TransferQueueRowView: View {
    let snapshot: TransferSnapshot
    let filter: TransferQueueFilter
    let palette: SparkleThemePalette
    let strings: AppStrings
    let onPause: () -> Void
    let onRetry: () -> Void
    let onCancel: () -> Void

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    var body: some View {
        HStack(spacing: 0) {
            switch filter {
            case .queued:
                localFileCell(minWidth: 160, maxWidth: .infinity)
                directionCell(width: 65)
                remoteFileCell(minWidth: 160, maxWidth: .infinity)
                sizeCell(width: 85)
                priorityCell(width: 65)
                statusCell(width: 180)
            case .failed:
                localFileCell(minWidth: 150, maxWidth: .infinity)
                directionCell(width: 65)
                remoteFileCell(minWidth: 150, maxWidth: .infinity)
                sizeCell(width: 85)
                priorityCell(width: 65)
                timeCell(width: 75)
                reasonCell(minWidth: 150, maxWidth: .infinity)
            case .successful:
                localFileCell(minWidth: 180, maxWidth: .infinity)
                directionCell(width: 65)
                remoteFileCell(minWidth: 180, maxWidth: .infinity)
                sizeCell(width: 85)
                priorityCell(width: 65)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .contextMenu {
            if snapshot.status.isActive || snapshot.status == .queued {
                Button(strings.t("transfers.pause"), action: onPause)
                Button(strings.t("common.cancel"), role: .destructive, action: onCancel)
            } else if snapshot.status != .completed {
                Button(strings.t("transfers.retry"), action: onRetry)
                if snapshot.status == .paused || snapshot.status == .interrupted {
                    Button(strings.t("common.cancel"), role: .destructive, action: onCancel)
                }
            }
        }
    }

    private func localFileCell(minWidth: CGFloat, maxWidth: CGFloat) -> some View {
        let localPath = snapshot.metadata.direction == .upload
            ? snapshot.metadata.source.displayPath
            : snapshot.metadata.destination.displayPath
        return Text(localPath)
            .font(SparkleTheme.Typography.caption)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(minWidth: minWidth, maxWidth: maxWidth, alignment: .leading)
            .padding(.horizontal, 4)
            .help(localPath)
    }

    private func directionCell(width: CGFloat) -> some View {
        HStack(spacing: 2) {
            Image(systemName: snapshot.metadata.direction == .upload ? "arrow.right" : "arrow.left")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(
                    snapshot.metadata.direction == .upload
                        ? palette.accentColor
                        : SparkleTheme.Colors.success
                )
        }
        .frame(width: width, alignment: .center)
        .padding(.horizontal, 4)
    }

    private func remoteFileCell(minWidth: CGFloat, maxWidth: CGFloat) -> some View {
        let remotePath = snapshot.metadata.direction == .upload
            ? snapshot.metadata.destination.displayPath
            : snapshot.metadata.source.displayPath
        return Text(remotePath)
            .font(SparkleTheme.Typography.caption)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(minWidth: minWidth, maxWidth: maxWidth, alignment: .leading)
            .padding(.horizontal, 4)
            .help(remotePath)
    }

    private func sizeCell(width: CGFloat) -> some View {
        let formattedSize = Self.byteFormatter.string(fromByteCount: snapshot.metadata.totalBytes)
        return Text(formattedSize)
            .font(SparkleTheme.Typography.caption)
            .lineLimit(1)
            .frame(width: width, alignment: .trailing)
            .padding(.horizontal, 4)
    }

    private func priorityCell(width: CGFloat) -> some View {
        Text(priorityString)
            .font(SparkleTheme.Typography.caption)
            .lineLimit(1)
            .foregroundStyle(palette.secondaryTextColor)
            .frame(width: width, alignment: .center)
            .padding(.horizontal, 4)
    }

    private var priorityString: String {
        switch snapshot.metadata.priority {
        case .low: return "Low"
        case .normal: return "Normal"
        case .high: return "High"
        }
    }

    private func statusCell(width: CGFloat) -> some View {
        HStack(spacing: 4) {
            if snapshot.status.isActive {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text("\(Int(snapshot.progress.percentage * 100))%")
                            .font(.system(size: 10, weight: .semibold))
                        if snapshot.progress.bytesPerSecond > 0 {
                            Text("\(Self.byteFormatter.string(fromByteCount: snapshot.progress.bytesPerSecond))/s")
                                .font(.system(size: 9))
                                .foregroundStyle(palette.secondaryTextColor)
                        }
                    }
                    TransferProgressBar(fraction: snapshot.progress.percentage, tint: statusTint)
                        .frame(height: 3)
                }
            } else {
                Text(statusDisplayString)
                    .font(SparkleTheme.Typography.caption)
                    .foregroundStyle(statusTint)
                    .lineLimit(1)
            }
            Spacer(minLength: 2)
            rowButtons
        }
        .frame(width: width, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private func timeCell(width: CGFloat) -> some View {
        let date = snapshot.checkpoint?.updatedAt ?? snapshot.metadata.createdAt
        let timeString = Self.timeFormatter.string(from: date)
        return Text(timeString)
            .font(SparkleTheme.Typography.caption)
            .foregroundStyle(palette.secondaryTextColor)
            .lineLimit(1)
            .frame(width: width, alignment: .center)
            .padding(.horizontal, 4)
    }

    private func reasonCell(minWidth: CGFloat, maxWidth: CGFloat) -> some View {
        HStack(spacing: 4) {
            Text(failureReason)
                .font(SparkleTheme.Typography.caption)
                .foregroundStyle(SparkleTheme.Colors.danger)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 2)
            rowButtons
        }
        .frame(minWidth: minWidth, maxWidth: maxWidth, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private var statusDisplayString: String {
        snapshot.status.statusCode.capitalized
    }

    private var failureReason: String {
        if case let .failed(error) = snapshot.status {
            return error.errorDescription ?? strings.t("transfers.transferFailed")
        } else if snapshot.status == .cancelled {
            return strings.t("common.cancelled")
        }
        return ""
    }

    @ViewBuilder
    private var rowButtons: some View {
        if snapshot.status.isActive || snapshot.status == .queued {
            Button(action: onPause) {
                Image(systemName: "pause.circle")
            }
            .buttonStyle(.borderless)
            .help(strings.t("transfers.pause"))
            Button(action: onCancel) {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
            .help(strings.t("common.cancel"))
        } else if snapshot.status == .paused || snapshot.status == .interrupted {
            Button(action: onRetry) {
                Image(systemName: "play.circle")
            }
            .buttonStyle(.borderless)
            .help(strings.t("transfers.retry"))
            Button(action: onCancel) {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
            .help(strings.t("common.cancel"))
        } else if snapshot.status.isFailed || snapshot.status == .cancelled {
            Button(action: onRetry) {
                Image(systemName: "arrow.clockwise.circle")
            }
            .buttonStyle(.borderless)
            .help(strings.t("transfers.retry"))
        }
    }

    private var statusTint: Color {
        switch snapshot.status {
        case .completed: return SparkleTheme.Colors.success
        case .failed, .cancelled: return SparkleTheme.Colors.danger
        case .paused, .interrupted, .needsReview: return SparkleTheme.Colors.warning
        default: return SparkleTheme.Colors.accent
        }
    }
}
