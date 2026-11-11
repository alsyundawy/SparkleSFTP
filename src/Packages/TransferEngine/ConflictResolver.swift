import Foundation
import SparkleCore

public struct ConflictContext: Identifiable, Sendable, Equatable {
    public var id: UUID {
        taskID
    }

    public let taskID: UUID
    public let direction: TransferDirection
    public let sourceDisplayPath: String
    public let destinationDisplayPath: String
    public let existingSize: Int64
    public let incomingSize: Int64
    public let existingModifiedAt: Date?
    public let incomingModifiedAt: Date?

    public init(
        taskID: UUID,
        direction: TransferDirection = .upload,
        sourceDisplayPath: String = "",
        destinationDisplayPath: String,
        existingSize: Int64,
        incomingSize: Int64,
        existingModifiedAt: Date? = nil,
        incomingModifiedAt: Date? = nil
    ) {
        self.taskID = taskID
        self.direction = direction
        self.sourceDisplayPath = sourceDisplayPath
        self.destinationDisplayPath = destinationDisplayPath
        self.existingSize = existingSize
        self.incomingSize = incomingSize
        self.existingModifiedAt = existingModifiedAt
        self.incomingModifiedAt = incomingModifiedAt
    }

    public var supportsResume: Bool {
        existingSize > 0 && incomingSize > existingSize
    }
}

/// Resolves FileZilla-style file transfer conflicts with session/queue rules and bounded ask timeout (LOG-004).
public actor ConflictResolver {
    public typealias InteractivePrompt = @Sendable (ConflictContext) async -> TransferConflictResolution

    private var defaultPolicy: TransferConflictPolicy
    private var queueRuleAll: TransferConflictPolicy?
    private var queueRuleUploads: TransferConflictPolicy?
    private var queueRuleDownloads: TransferConflictPolicy?
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

    public func updateDefaultPolicy(_ policy: TransferConflictPolicy) {
        defaultPolicy = policy
    }

    public func applyQueueRule(_ policy: TransferConflictPolicy, scope: TransferConflictScope) {
        switch scope {
        case .all:
            queueRuleAll = policy
        case .uploadsOnly:
            queueRuleUploads = policy
        case .downloadsOnly:
            queueRuleDownloads = policy
        }
    }

    public func clearQueueRules() {
        queueRuleAll = nil
        queueRuleUploads = nil
        queueRuleDownloads = nil
    }

    public func resolve(
        _ context: ConflictContext,
        originalFilename: String,
        overridePolicy: TransferConflictPolicy? = nil
    ) async -> TransferConflictResolution {
        let directionRule = context.direction == .upload ? queueRuleUploads : queueRuleDownloads
        let activePolicy = directionRule ?? queueRuleAll ?? overridePolicy ?? defaultPolicy
        if activePolicy == .ask {
            return await askInteractively(context)
        }
        return Self.evaluateNonInteractivePolicy(
            activePolicy,
            context: context,
            originalFilename: originalFilename
        )
    }

    public static func evaluateNonInteractivePolicy(
        _ policy: TransferConflictPolicy,
        context: ConflictContext,
        originalFilename: String
    ) -> TransferConflictResolution {
        switch policy {
        case .ask, .skip:
            return .skip
        case .overwrite:
            return .overwrite
        case .overwriteIfNewer:
            return shouldOverwriteBecauseNewer(context) ? .overwrite : .skip
        case .overwriteIfDifferentSize:
            return context.incomingSize != context.existingSize ? .overwrite : .skip
        case .overwriteIfDifferentSizeOrNewer:
            let sizeDiffers = context.incomingSize != context.existingSize
            return (sizeDiffers || shouldOverwriteBecauseNewer(context)) ? .overwrite : .skip
        case .resume:
            if context.supportsResume {
                return .resume
            }
            return context.incomingSize == context.existingSize ? .skip : .overwrite
        case .rename:
            return .rename(newFilename: uniqueName(from: originalFilename))
        }
    }

    private static func shouldOverwriteBecauseNewer(_ context: ConflictContext) -> Bool {
        guard let incoming = context.incomingModifiedAt else {
            return false
        }
        guard let existing = context.existingModifiedAt else {
            return true
        }
        return incoming.timeIntervalSince(existing) > 1.0
    }

    private func askInteractively(_ context: ConflictContext) async -> TransferConflictResolution {
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

    public static func uniqueName(from filename: String) -> String {
        let url = URL(fileURLWithPath: filename)
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let shortNonce = UUID().uuidString.prefix(4).lowercased()
        let suffix = "copy-\(Int(Date().timeIntervalSince1970))-\(shortNonce)"
        return ext.isEmpty ? "\(base)-\(suffix)" : "\(base)-\(suffix).\(ext)"
    }
}
