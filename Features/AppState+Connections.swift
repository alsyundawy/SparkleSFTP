import Foundation
import SparkleCore
import SparkleFileManager
import SparkleNetworking

extension AppState {
    public func bootstrap() async {
        await refreshProfilesAndGroups()
        await refreshLocalDirectory(localCurrentURL)
        trustedHosts = await hostTrustStore.allTrustedHosts()
        if let loadedSnippets = try? await snippetStore.loadSnippets() {
            snippets = loadedSnippets
        }
        startTransferObserver()
        if let restored = try? await transferQueue.restoreInterruptedFromJournal(), !restored.isEmpty {
            transferSnapshots = restored
        }
    }

    public func refreshProfilesAndGroups() async {
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

    public func saveProfile(_ profile: ConnectionProfile, secretString: String?) async {
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
            try await connectionStore.saveProfile(mutable)
            await refreshProfilesAndGroups()
            selectedProfileID = mutable.id
        } catch {
            lastError = (error as? AppError) ?? .persistenceFailure(reason: error.localizedDescription)
        }
    }

    public func deleteProfile(_ profile: ConnectionProfile) async {
        do {
            if let passRef = profile.passwordRef { try? await credentialStore.deleteSecret(for: passRef) }
            if let keyRef = profile.privateKeyRef { try? await credentialStore.deleteSecret(for: keyRef) }
            try await connectionStore.deleteProfile(id: profile.id)
            await refreshProfilesAndGroups()
        } catch {
            lastError = (error as? AppError) ?? .persistenceFailure(reason: error.localizedDescription)
        }
    }

    public func connect(profile: ConnectionProfile) async {
        if profile.requireTouchID && featureFlags.isTouchIDGateEnabled {
            do {
                let reason = "Authenticate to connect to \(profile.name)"
                try await credentialStore.evaluateBiometricPolicy(reason: reason)
            } catch {
                lastError = (error as? AppError)
                    ?? .biometricAuthenticationFailed(reason: error.localizedDescription)
                return
            }
        }

        let created = RemoteServiceFactory.makeService(
            for: profile,
            credentialStore: credentialStore,
            hostTrustStore: hostTrustStore
        ) { [weak self] challenge in
            guard let self else { return false }
            return await self.promptHostKeyChallenge(challenge)
        }

        do {
            try await created.service.connection.connect()
            var updatedProfile = profile
            updatedProfile.lastConnectedAt = Date()
            try? await connectionStore.saveProfile(updatedProfile)
            await refreshProfilesAndGroups()
            trustedHosts = await hostTrustStore.allTrustedHosts()

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
        } catch let appError as AppError {
            if case .hostKeyMismatch = appError {
                hostMismatchAlert = appError
            }
            lastError = appError
        } catch {
            lastError = .transferFailed(reason: error.localizedDescription)
        }
    }

    public func disconnect(sessionID: UUID) async {
        guard let idx = activeSessions.firstIndex(where: { $0.id == sessionID }) else { return }
        let removed = activeSessions.remove(at: idx)
        try? await removed.service.connection.disconnect(policy: .cancelAllTransfers)
        if activeSessionID == sessionID {
            activeSessionID = activeSessions.last?.id
        }
    }
}
