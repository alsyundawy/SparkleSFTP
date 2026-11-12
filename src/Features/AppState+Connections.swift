import Foundation
import SparkleCore
import SparkleDesignSystem
import SparkleFileManager
import SparkleNetworking
import SparkleTransferEngine
import UserNotifications

public extension AppState {
    internal func notifyTerminalTransfersIfNeeded(_ snapshots: [TransferSnapshot]) {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        let isQueueBusy = snapshots.contains { $0.status.isActive || $0.status == .queued }
        let newlyTerminal = snapshots.filter {
            ($0.status == .completed || $0.status.isFailed) && !notifiedTerminalTransferIDs.contains($0.id)
        }
        guard !newlyTerminal.isEmpty else { return }
        if isQueueBusy, snapshots.count > 5 {
            return
        }
        for snap in newlyTerminal {
            notifiedTerminalTransferIDs.insert(snap.id)
        }
        let content = makeTransferNotificationContent(for: newlyTerminal)
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req) { _ in }
    }

    private func makeTransferNotificationContent(
        for newlyTerminal: [TransferSnapshot]
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        if newlyTerminal.count == 1, let single = newlyTerminal.first {
            if case let .failed(error) = single.status {
                content.title = "Transfer Failed"
                content.body = error.errorDescription ?? single.metadata.destination.displayPath
            } else {
                content.title = "Transfer Completed"
                content.body = single.metadata.destination.displayPath
            }
            return content
        }
        let failedCount = newlyTerminal.count(where: \.status.isFailed)
        let completedCount = newlyTerminal.count - failedCount
        content.title = failedCount > 0 ? "Transfers Finished with Issues" : "Transfers Completed"
        content.body = "\(completedCount) completed, \(failedCount) failed"
        return content
    }

    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true
        if Bundle.main.bundleURL.pathExtension == "app" {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        }
        await refreshProfilesAndGroups()
        let dirSignpostID = SparkleSignposts.launch.makeSignpostID()
        let dirState = SparkleSignposts.launch.beginInterval("InitialDirectoryListing", id: dirSignpostID)
        await refreshLocalDirectory(localCurrentURL, recordHistory: false)
        SparkleSignposts.launch.endInterval("InitialDirectoryListing", dirState)
        trustedHosts = await hostTrustStore.allTrustedHosts()
        if let loadedSnippets = try? await snippetStore.loadSnippets() {
            snippets = loadedSnippets
        }
        startTransferObserver()
        if let restored = try? await transferQueue.restoreInterruptedFromJournal(), !restored.isEmpty {
            transferSnapshots = restored
        }
        applyAutoUpdateConfiguration()
        Task { [weak self] in
            await self?.refreshToolchainReport()
        }
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
            broadcastConnectionsDidChange()
        } catch {
            lastError = (error as? AppError) ?? .persistenceFailure(reason: error.localizedDescription)
        }
    }

    func deleteGroup(id: UUID) async {
        do {
            try await connectionStore.deleteGroup(id: id)
            await refreshProfilesAndGroups()
            broadcastConnectionsDidChange()
        } catch {
            lastError = (error as? AppError) ?? .persistenceFailure(reason: error.localizedDescription)
        }
    }

    func saveProfile(
        _ profile: ConnectionProfile,
        secretString: String?,
        passphraseString: String? = nil,
        clearStoredSecrets: Bool = false
    ) async {
        do {
            var mutable = profile
            if clearStoredSecrets {
                await deleteProfileSecrets(mutable)
                mutable.passwordRef = nil
                mutable.privateKeyRef = nil
                mutable.passphraseRef = nil
            }
            if !clearStoredSecrets, let secret = secretString, !secret.isEmpty {
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
            if !clearStoredSecrets, let passphrase = passphraseString, !passphrase.isEmpty {
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
            broadcastConnectionsDidChange()
        } catch {
            lastError = (error as? AppError) ?? .persistenceFailure(reason: error.localizedDescription)
        }
    }

    func connect(profile: ConnectionProfile, openInNewTab: Bool = false) async {
        guard openInNewTab || !connectingProfileIDs.contains(profile.id) else { return }
        connectingProfileIDs.insert(profile.id)
        pendingPromptedSecretToRemember = nil
        defer {
            connectingProfileIDs.remove(profile.id)
            pendingPromptedSecretToRemember = nil
            let key = "\(profile.host):\(profile.port):\(profile.username)"
            transientQuickConnectSecrets.removeValue(forKey: key)
        }

        guard await authenticateBiometricsIfNeeded(for: profile) else { return }
        let created = buildRemoteService(for: profile)
        ActivityLogger.shared.logStatus(
            "Connecting to \(profile.host):\(profile.port) via \(profile.protocolType.rawValue.uppercased())..."
        )

        var didConnectTransport = false
        var committedSession = false
        do {
            try await created.service.connection.connect()
            didConnectTransport = true
            try await finalizeSuccessfulConnection(
                profile: profile,
                created: created,
                openInNewTab: openInNewTab
            )
            committedSession = true
            ActivityLogger.shared.logStatus(
                "Connected to \(profile.name) (\(profile.host):\(profile.port))."
            )
        } catch let appError as AppError {
            if didConnectTransport, !committedSession {
                try? await created.service.connection.disconnect(policy: .cancelAllTransfers)
            }
            if case .hostKeyMismatch = appError {
                hostMismatchAlert = appError
            }
            lastError = appError
            ActivityLogger.shared.logError("Connection failed: \(appError.localizedDescription)")
        } catch is CancellationError {
            if didConnectTransport, !committedSession {
                try? await created.service.connection.disconnect(policy: .cancelAllTransfers)
            }
            ActivityLogger.shared.logStatus("Connection cancelled.")
            return
        } catch {
            if didConnectTransport, !committedSession {
                try? await created.service.connection.disconnect(policy: .cancelAllTransfers)
            }
            ActivityLogger.shared.logError("Connection error: \(error.localizedDescription)")
            reportNonCancellationError(error)
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
            options: RemoteTransportOptions(
                pipelineDepth: transferPipelineDepth,
                useCompression: useZlibCompression
            ),
            hostTrustPrompt: { [weak self] challenge in
                guard let self else { return false }
                return await promptHostKeyChallenge(challenge)
            }
        )
    }

    private func finalizeSuccessfulConnection(
        profile: ConnectionProfile,
        created: (service: RemoteService, sshClient: SSHClientService?),
        openInNewTab: Bool
    ) async throws {
        var updatedProfile = profile
        if let promptedSecret = pendingPromptedSecretToRemember, !promptedSecret.isEmpty {
            let ref = updatedProfile.passwordRef ?? SecretReference(kind: .password)
            if await (try? credentialStore.saveSecret(
                Data(promptedSecret.utf8),
                for: ref,
                requireTouchID: updatedProfile.requireTouchID
            )) != nil {
                updatedProfile.passwordRef = ref
            }
            pendingPromptedSecretToRemember = nil
        }
        updatedProfile.lastConnectedAt = Date()
        if profiles.contains(where: { $0.id == updatedProfile.id }) {
            try? await connectionStore.saveProfile(updatedProfile)
            await refreshProfilesAndGroups()
            broadcastConnectionsDidChange()
        }
        trustedHosts = await hostTrustStore.allTrustedHosts()

        if openInNewTab {
            syncCurrentTabLocalSnapshot()
        }
        if let localDefault = profile.defaultLocalPath, !localDefault.isEmpty,
           FileManager.default.fileExists(atPath: localDefault) {
            await refreshLocalDirectory(URL(fileURLWithPath: localDefault))
        }

        let listed = try await created.service.fileSystem.listDirectory(at: profile.defaultRemotePath)
        let sorted = await FileSortDescriptor.sortRemoteFiles(listed, by: FileSortDescriptor())
        let session = ActiveSessionModel(
            id: UUID(),
            profile: updatedProfile,
            service: created.service,
            sshClient: created.sshClient,
            currentRemotePath: profile.defaultRemotePath,
            remoteFiles: PaginatedFileWindow(allFiles: sorted),
            sortDescriptor: FileSortDescriptor(),
            selectedRemoteFileIDs: []
        )
        activeSessions.append(session)
        attachConnectedSession(session, openInNewTab: openInNewTab)
        activeSessionID = session.id
        activePane = .right
        statusBannerMessage = "Connected to \(profile.host)"
    }

    func disconnect(sessionID: UUID) async {
        guard let idx = activeSessions.firstIndex(where: { $0.id == sessionID }) else { return }
        let removed = activeSessions.remove(at: idx)
        ActivityLogger.shared.logStatus("Disconnected from \(removed.profile.name) (\(removed.profile.host)).")
        terminalManager.closeSessions(forRemoteSessionID: sessionID)
        try? await removed.service.connection.disconnect(policy: .cancelAllTransfers)

        for tabIdx in workspaceTabs.indices where workspaceTabs[tabIdx].sessionID == sessionID {
            workspaceTabs[tabIdx].sessionID = nil
            workspaceTabs[tabIdx].title = strings.t("tabs.newTab")
            workspaceTabs[tabIdx].isTerminalVisible = false
        }
        if activeSessionID == sessionID {
            activeSessionID = currentTab?.sessionID
            if currentTab?.sessionID == nil {
                isTerminalVisible = false
                terminalManager.selectedSessionID = nil
            } else if let tab = currentTab {
                isTerminalVisible = tab.isTerminalVisible
                terminalManager.selectedSessionID = terminalManager.session(forWorkspaceTabID: tab.id)?.id
            }
        }
        if activeSessions.isEmpty {
            for (dirURL, watcher) in remoteEditWatches {
                watcher.stopWatching()
                try? FileManager.default.removeItem(at: dirURL)
            }
            remoteEditWatches.removeAll()
        }
    }

    func disconnectAllSessions(forProfileID profileID: UUID) async {
        let matchingIDs = activeSessions.filter { $0.profile.id == profileID }.map(\.id)
        for sessionID in matchingIDs {
            await disconnect(sessionID: sessionID)
        }
    }
}
