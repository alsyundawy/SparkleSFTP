import Foundation
import SparkleCore
import SparkleNetworking
import SparkleTransferEngine

public extension AppState {
    func resolveHostChallenge(trusted: Bool) {
        pendingHostChallenge = nil
        hostChallengeContinuation?.resume(returning: trusted)
        hostChallengeContinuation = nil
    }

    func resolveCredentialPrompt(_ secret: String?, remember: Bool = false) {
        pendingPromptedSecretToRemember = (remember && !(secret ?? "").isEmpty) ? secret : nil
        pendingCredentialPrompt = nil
        credentialPromptContinuation?.resume(returning: secret)
        credentialPromptContinuation = nil
    }

    func resolveConflict(
        _ resolution: TransferConflictResolution,
        applyToQueue: Bool = false,
        queuePolicy: TransferConflictPolicy? = nil,
        scope: TransferConflictScope = .all
    ) {
        handleConflictResolution(
            resolution,
            applyToQueue: applyToQueue,
            queuePolicy: queuePolicy,
            scope: scope
        )
    }

    func cancelPendingHostChallengeIfNeeded() {
        guard hostChallengeContinuation != nil else { return }
        resolveHostChallenge(trusted: false)
    }

    func cancelPendingCredentialPromptIfNeeded() {
        guard credentialPromptContinuation != nil else { return }
        resolveCredentialPrompt(nil, remember: false)
    }

    func cancelPendingConflictIfNeeded() {
        guard !pendingConflictQueue.isEmpty else { return }
        handleConflictResolution(.skip, applyToQueue: false, queuePolicy: nil, scope: .all)
    }

    internal func promptHostKeyChallenge(_ challenge: HostKeyChallenge) async -> Bool {
        await withCheckedContinuation { continuation in
            hostChallengeContinuation = continuation
            pendingHostChallenge = challenge
        }
    }

    internal func promptCredential(_ request: CredentialPromptRequest) async -> String? {
        let key = "\(request.host):\(request.port):\(request.username)"
        if let transient = transientQuickConnectSecrets.removeValue(forKey: key),
           !transient.isEmpty {
            return transient
        }
        return await withCheckedContinuation { continuation in
            credentialPromptContinuation = continuation
            pendingCredentialPrompt = request
        }
    }

    internal func promptConflictResolution(_ context: ConflictContext) async -> TransferConflictResolution {
        await withCheckedContinuation { continuation in
            enqueueConflictPrompt(context, continuation: continuation)
        }
    }

    internal func enqueueConflictPrompt(
        _ context: ConflictContext,
        continuation: CheckedContinuation<TransferConflictResolution, Never>
    ) {
        if let stickyPolicy = activeConflictRule(for: context.direction) {
            let name = URL(fileURLWithPath: context.destinationDisplayPath).lastPathComponent
            let auto = ConflictResolver.evaluateNonInteractivePolicy(
                stickyPolicy,
                context: context,
                originalFilename: name
            )
            continuation.resume(returning: auto)
            return
        }
        pendingConflictQueue.append(ConflictPromptEntry(context: context, continuation: continuation))
        if pendingConflict == nil {
            pendingConflict = pendingConflictQueue.first?.context
        }
    }

    internal func handleConflictResolution(
        _ resolution: TransferConflictResolution,
        applyToQueue: Bool,
        queuePolicy: TransferConflictPolicy?,
        scope: TransferConflictScope
    ) {
        if applyToQueue, let policy = queuePolicy {
            activeQueueConflictRules[scope] = policy
            hasActiveConflictQueueRules = true
            Task { await transferQueue.applyConflictRule(policy, scope: scope) }
        }
        guard !pendingConflictQueue.isEmpty else {
            pendingConflict = nil
            return
        }
        let first = pendingConflictQueue.removeFirst()
        first.continuation.resume(returning: resolution)
        drainAutoResolvedConflictsIfNeeded()
    }

    private func drainAutoResolvedConflictsIfNeeded() {
        var remaining: [ConflictPromptEntry] = []
        for entry in pendingConflictQueue {
            if let stickyPolicy = activeConflictRule(for: entry.context.direction) {
                let name = URL(fileURLWithPath: entry.context.destinationDisplayPath).lastPathComponent
                let auto = ConflictResolver.evaluateNonInteractivePolicy(
                    stickyPolicy,
                    context: entry.context,
                    originalFilename: name
                )
                entry.continuation.resume(returning: auto)
            } else {
                remaining.append(entry)
            }
        }
        pendingConflictQueue = remaining
        pendingConflict = pendingConflictQueue.first?.context
    }

    private func activeConflictRule(for direction: TransferDirection) -> TransferConflictPolicy? {
        let dirScope: TransferConflictScope = direction == .upload ? .uploadsOnly : .downloadsOnly
        return activeQueueConflictRules[dirScope] ?? activeQueueConflictRules[.all]
    }
}
