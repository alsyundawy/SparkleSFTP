import Foundation
import SparkleCore
import SparkleDesignSystem
import SparkleFileManager
import SparkleNetworking
import SparkleTransferEngine
import UserNotifications

public extension AppState {
    internal func promptHostKeyChallenge(_ challenge: HostKeyChallenge) async -> Bool {
        await withCheckedContinuation { continuation in
            hostChallengeContinuation = continuation
            pendingHostChallenge = challenge
        }
    }

    internal func promptCredential(_ request: CredentialPromptRequest) async -> String? {
        await withCheckedContinuation { continuation in
            credentialPromptContinuation = continuation
            pendingCredentialPrompt = request
        }
    }

    internal func promptConflictResolution(_ context: ConflictContext) async -> TransferConflictResolution {
        await withCheckedContinuation { continuation in
            conflictContinuation = continuation
            pendingConflict = context
        }
    }

    internal func notifyTerminalTransfersIfNeeded(_ snapshots: [TransferSnapshot]) {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        for snap in snapshots where !notifiedTerminalTransferIDs.contains(snap.id) {
            let content = UNMutableNotificationContent()
            switch snap.status {
            case .completed:
                content.title = "Transfer Completed"
                content.body = snap.metadata.destination.displayPath
            case let .failed(error):
                content.title = "Transfer Failed"
                content.body = error.errorDescription ?? snap.metadata.destination.displayPath
            default:
                continue
            }
            notifiedTerminalTransferIDs.insert(snap.id)
            let req = UNNotificationRequest(identifier: snap.id.uuidString, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(req) { _ in }
        }
    }

    func bootstrap() async {
        if Bundle.main.bundleURL.pathExtension == "app" {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        }
        await refreshProfilesAndGroups()
        await refreshLocalDirectory(localCurrentURL, recordHistory: false)
        trustedHosts = await hostTrustStore.allTrustedHosts()
        if let loadedSnippets = try? await snippetStore.loadSnippets() {
            snippets = loadedSnippets
        }
        startTransferObserver()
        if let restored = try? await transferQueue.restoreInterruptedFromJournal(), !restored.isEmpty {
            transferSnapshots = restored
        }
        applyAutoUpdateConfiguration()
        if autoUpdateSettings.isOverdue {
            Task { [weak self] in
                await self?.checkForUpdates(manual: false)
            }
        }
    }

    func refreshProfilesAndGroups() async {
        do {
            profiles = try await connectionStore.loadProfiles()
            groups = try await connectionStore.loadGroups()
            if selectedProfileID == nil {
                selectedProfileID = profiles.first?.id
            }
        } catch {
            lastError = (error as? AppError) ?? .persistenceFailure(reason: error.localizedDescription)
        }
    }

    func createGroup(named name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let group = ServerGroup(name: trimmed, sortOrder: groups.count)
        do {
            try await connectionStore.saveGroup(group)
            await refreshProfilesAndGroups()
        } catch {
            lastError = (error as? AppError) ?? .persistenceFailure(reason: error.localizedDescription)
        }
    }

    func deleteGroup(id: UUID) async {
        do {
            try await connectionStore.deleteGroup(id: id)
            await refreshProfilesAndGroups()
        } catch {
            lastError = (error as? AppError) ?? .persistenceFailure(reason: error.localizedDescription)
        }
    }

    func saveProfile(
        _ profile: ConnectionProfile,
        secretString: String?,
        passphraseString: String? = nil
    ) async {
        do {
            var mutable = profile
            if let secret = secretString, !secret.isEmpty {
                let requireTouchID = mutable.requireTouchID
                if mutable.authMethod == .publicKey {
                    let keyRef = mutable.privateKeyRef ?? SecretReference(kind: .privateKey)
                    try await credentialStore.saveSecret(
                        Data(secret.utf8),
                        for: keyRef,
                        requireTouchID: requireTouchID
                    )
                    mutable.privateKeyRef = keyRef
                } else {
                    let ref = mutable.passwordRef ?? SecretReference(kind: .password)
                    try await credentialStore.saveSecret(
                        Data(secret.utf8),
                        for: ref,
                        requireTouchID: requireTouchID
                    )
                    mutable.passwordRef = ref
                }
            }
            if let passphrase = passphraseString, !passphrase.isEmpty {
                let passRef = mutable.passphraseRef ?? SecretReference(kind: .keyPassphrase)
                try await credentialStore.saveSecret(
                    Data(passphrase.utf8),
                    for: passRef,
                    requireTouchID: mutable.requireTouchID
                )
                mutable.passphraseRef = passRef
            }
            try await connectionStore.saveProfile(mutable)
            await refreshProfilesAndGroups()
            selectedProfileID = mutable.id
        } catch {
            lastError = (error as? AppError) ?? .persistenceFailure(reason: error.localizedDescription)
        }
    }

    func connect(profile: ConnectionProfile) async {
        guard !connectingProfileIDs.contains(profile.id) else { return }
        connectingProfileIDs.insert(profile.id)
        defer { connectingProfileIDs.remove(profile.id) }

        guard await authenticateBiometricsIfNeeded(for: profile) else { return }
        let created = buildRemoteService(for: profile)

        do {
            try await created.service.connection.connect()
            try await finalizeSuccessfulConnection(profile: profile, created: created)
        } catch let appError as AppError {
            if case .hostKeyMismatch = appError {
                hostMismatchAlert = appError
            }
            lastError = appError
        } catch {
            lastError = .transferFailed(reason: error.localizedDescription)
        }
    }

    private func authenticateBiometricsIfNeeded(for profile: ConnectionProfile) async -> Bool {
        guard profile.requireTouchID, featureFlags.isTouchIDGateEnabled else { return true }
        do {
            let reason = "Authenticate to connect to \(profile.name)"
            try await credentialStore.evaluateBiometricPolicy(reason: reason)
            return true
        } catch {
            lastError = (error as? AppError)
                ?? .biometricAuthenticationFailed(reason: error.localizedDescription)
            return false
        }
    }

    private func buildRemoteService(for profile: ConnectionProfile) -> (
        service: RemoteService,
        sshClient: SSHClientService?
    ) {
        RemoteServiceFactory.makeService(
            for: profile,
            credentialStore: credentialStore,
            hostTrustStore: hostTrustStore,
            credentialPrompt: { [weak self] request in
                guard let self else { return nil }
                return await promptCredential(request)
            },
            jumpProfileResolver: { [weak self] jumpID in
                guard let self else { return nil }
                return await MainActor.run {
                    self.profiles.first { $0.id == jumpID }
                }
            },
            hostTrustPrompt: { [weak self] challenge in
                guard let self else { return false }
                return await promptHostKeyChallenge(challenge)
            }
        )
    }

    private func finalizeSuccessfulConnection(
        profile: ConnectionProfile,
        created: (service: RemoteService, sshClient: SSHClientService?)
    ) async throws {
        var updatedProfile = profile
        updatedProfile.lastConnectedAt = Date()
        try? await connectionStore.saveProfile(updatedProfile)
        await refreshProfilesAndGroups()
        trustedHosts = await hostTrustStore.allTrustedHosts()

        if let localDefault = profile.defaultLocalPath, !localDefault.isEmpty,
           FileManager.default.fileExists(atPath: localDefault) {
            await refreshLocalDirectory(URL(fileURLWithPath: localDefault))
        }

        let listed = try await created.service.fileSystem.listDirectory(at: profile.defaultRemotePath)
        let sorted = await FileSortDescriptor.sortRemoteFiles(listed, by: FileSortDescriptor())
        let session = ActiveSessionModel(
            id: profile.id,
            profile: updatedProfile,
            service: created.service,
            sshClient: created.sshClient,
            currentRemotePath: profile.defaultRemotePath,
            remoteFiles: PaginatedFileWindow(allFiles: sorted),
            sortDescriptor: FileSortDescriptor(),
            selectedRemoteFileIDs: []
        )
        activeSessions.removeAll { $0.id == session.id }
        activeSessions.append(session)
        activeSessionID = session.id
        activePane = .right
        statusBannerMessage = "Connected to \(profile.host)"
    }

    func disconnect(sessionID: UUID) async {
        guard let idx = activeSessions.firstIndex(where: { $0.id == sessionID }) else { return }
        let removed = activeSessions.remove(at: idx)
        try? await removed.service.connection.disconnect(policy: .cancelAllTransfers)
        if activeSessionID == sessionID {
            activeSessionID = activeSessions.last?.id
        }
        if activeSessions.isEmpty {
            for (dirURL, watcher) in remoteEditWatches {
                watcher.stopWatching()
                try? FileManager.default.removeItem(at: dirURL)
            }
            remoteEditWatches.removeAll()
        }
    }
}
