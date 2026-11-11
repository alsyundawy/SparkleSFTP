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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            headerRow
            if case let .failed(error) = snapshot.status {
                Text(error.errorDescription ?? strings.t("transfers.transferFailed"))
                    .font(SparkleTheme.Typography.caption)
                    .foregroundStyle(SparkleTheme.Colors.danger)
                    .lineLimit(2)
            }
            TransferProgressBar(
                fraction: snapshot.status == .completed ? 1.0 : snapshot.progress.percentage,
                tint: statusTint
            )
            footerRow
        }
        .padding(.vertical, 2)
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

    private var headerRow: some View {
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
            StatusPill(title: snapshot.status.statusCode, systemImage: "circle.fill", tint: statusTint)
            rowButtons
        }
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

    private var footerRow: some View {
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
        .foregroundStyle(palette.secondaryTextColor)
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
