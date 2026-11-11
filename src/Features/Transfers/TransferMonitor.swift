import Foundation
import SparkleCore

/// Dedicated MainActor observable state for `TransferQueueView` so high-frequency transfer
/// progress updates do not invalidate unrelated main-window subviews.
@MainActor
public final class TransferMonitor: ObservableObject {
    @Published public var snapshots: [TransferSnapshot] = []

    public init() {}
}
