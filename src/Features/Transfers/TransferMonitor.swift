import Foundation
import SparkleCore

/// Dedicated MainActor observable state for `TransferQueueView` so high-frequency transfer
/// progress updates do not invalidate unrelated main-window subviews.
@MainActor
public final class TransferMonitor: ObservableObject {
    @Published public var snapshots: [TransferSnapshot] = []

    private var pendingSnapshots: [TransferSnapshot]?
    private var throttleTask: Task<Void, Never>?
    private var lastPublishedTime: Date = .distantPast
    private let minPublishInterval: TimeInterval = 0.08 // ~12.5 Hz (10–15 Hz)

    public init() {}

    public func updateSnapshots(_ newSnapshots: [TransferSnapshot], immediate: Bool = false) {
        let now = Date()
        let hasTerminalOrCountChange = immediate
            || newSnapshots.count != snapshots.count
            || newSnapshots.contains(where: { snap in
                snap.status.isTerminal && (snapshots.first(where: { $0.id == snap.id })?.status != snap.status)
            })

        if hasTerminalOrCountChange || now.timeIntervalSince(lastPublishedTime) >= minPublishInterval {
            throttleTask?.cancel()
            throttleTask = nil
            pendingSnapshots = nil
            lastPublishedTime = now
            snapshots = newSnapshots
            return
        }

        pendingSnapshots = newSnapshots
        guard throttleTask == nil else { return }

        throttleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(80))
            guard let self, !Task.isCancelled else { return }
            throttleTask = nil
            if let pending = pendingSnapshots {
                pendingSnapshots = nil
                lastPublishedTime = Date()
                snapshots = pending
            }
        }
    }
}
