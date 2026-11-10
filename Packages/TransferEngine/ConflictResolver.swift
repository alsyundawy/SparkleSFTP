import Foundation
import SparkleCore

public struct ConflictContext: Identifiable, Sendable, Equatable {
    public var id: UUID { taskID }
    public let taskID: UUID
    public let destinationDisplayPath: String
    public let existingSize: Int64
    public let incomingSize: Int64
}

/// Resolves file name conflicts with bounded ask timeout so queue admission never deadlocks offline (LOG-004).
public actor ConflictResolver {
    public typealias InteractivePrompt = @Sendable (ConflictContext) async -> TransferConflictResolution

    private let defaultPolicy: TransferConflictPolicy
    private let promptTimeoutSeconds: Int
    private let interactivePrompt: InteractivePrompt?

    public init(
        defaultPolicy: TransferConflictPolicy = .ask,
        promptTimeoutSeconds: Int = 120,
        interactivePrompt: InteractivePrompt? = nil
    ) {
        self.defaultPolicy = defaultPolicy
        self.promptTimeoutSeconds = max(1, promptTimeoutSeconds)
        self.interactivePrompt = interactivePrompt
    }

    public func resolve(_ context: ConflictContext, originalFilename: String) async -> TransferConflictResolution {
        switch defaultPolicy {
        case .skip:
            return .skip
        case .overwrite:
            return .overwrite
        case .rename:
            return .rename(newFilename: Self.uniqueName(from: originalFilename))
        case .ask:
            guard let interactivePrompt else {
                return .skip
            }
            let timeout = promptTimeoutSeconds
            return await withTaskGroup(of: TransferConflictResolution.self) { group in
                group.addTask {
                    await interactivePrompt(context)
                }
                group.addTask {
                    try? await Task.sleep(for: .seconds(timeout))
                    return .skip
                }
                let first = await group.next() ?? .skip
                group.cancelAll()
                return first
            }
        }
    }

    public static func uniqueName(from filename: String) -> String {
        let url = URL(fileURLWithPath: filename)
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let suffix = "copy-\(Int(Date().timeIntervalSince1970))"
        return ext.isEmpty ? "\(base)-\(suffix)" : "\(base)-\(suffix).\(ext)"
    }
}
