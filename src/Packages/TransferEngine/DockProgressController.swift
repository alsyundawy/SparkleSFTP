import AppKit
import Foundation
import SparkleCore

/// Controls application Dock icon badge and progress state reflecting active transfers.
@MainActor
public final class DockProgressController {
    public static let shared = DockProgressController()

    private init() {}

    private var dockTile: NSDockTile? {
        guard Bundle.main.bundleURL.pathExtension == "app", NSApp != nil else { return nil }
        return NSApp.dockTile
    }

    public func updateDockProgress(from snapshots: [TransferSnapshot]) {
        guard let tile = dockTile else { return }
        let active = snapshots.filter { $0.status.isActive || $0.status == .queued }
        guard !active.isEmpty else {
            clearDockProgress()
            return
        }

        var totalBytes: Int64 = 0
        var transferredBytes: Int64 = 0
        for item in active {
            totalBytes += item.progress.totalBytes
            transferredBytes += item.progress.bytesTransferred
        }

        if totalBytes > 0 {
            let ratio = Double(transferredBytes) / Double(totalBytes)
            let percentage = Int(min(1.0, max(0.0, ratio)) * 100)
            tile.badgeLabel = "\(percentage)%"
        } else {
            tile.badgeLabel = "\(active.count)"
        }
        tile.display()
    }

    public func clearDockProgress() {
        guard let tile = dockTile else { return }
        if tile.badgeLabel != nil {
            tile.badgeLabel = nil
            tile.display()
        }
    }
}
