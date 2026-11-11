import Foundation
import SparkleCore
import SparkleTerminal

public extension AppState {
    var selectedProfileID: UUID? {
        get { primarySelectedProfile?.id ?? selectedProfileIDs.first }
        set { selectedProfileIDs = newValue.map { [$0] } ?? [] }
    }

    var primarySelectedProfile: ConnectionProfile? {
        profiles.first { selectedProfileIDs.contains($0.id) }
    }

    var transferSnapshots: [TransferSnapshot] {
        get { transferMonitor.snapshots }
        set { transferMonitor.snapshots = newValue }
    }

    var hasActiveAsyncCleanup: Bool {
        !activeSessions.isEmpty || !activeTunnels.isEmpty
    }

    var currentSession: ActiveSessionModel? {
        activeSessions.first { $0.id == activeSessionID }
    }

    var recentProfiles: [ConnectionProfile] {
        profiles
            .filter { $0.lastConnectedAt != nil }
            .sorted { ($0.lastConnectedAt ?? .distantPast) > ($1.lastConnectedAt ?? .distantPast) }
    }

    var filteredProfiles: [ConnectionProfile] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return profiles }
        return profiles.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
                || $0.host.localizedCaseInsensitiveContains(trimmed)
                || $0.username.localizedCaseInsensitiveContains(trimmed)
        }
    }

    func selectAllVisibleProfiles() {
        selectedProfileIDs = Set(filteredProfiles.map(\.id))
    }

    func openAboutWindow() {
        aboutWindowController.present(appState: self)
    }

    func hasSavedSecret(for profile: ConnectionProfile?) async -> Bool {
        guard let profile else { return false }
        let targetRef = profile.authMethod == .publicKey ? profile.privateKeyRef : profile.passwordRef
        guard let targetRef else { return false }
        return await credentialStore.hasSecret(for: targetRef)
    }

    func deleteProfileSecrets(_ profile: ConnectionProfile) async {
        for ref in [profile.passwordRef, profile.privateKeyRef, profile.passphraseRef].compactMap(\.self) {
            try? await credentialStore.deleteSecret(for: ref)
        }
    }

    func deleteProfile(_ profile: ConnectionProfile) async {
        await deleteProfiles(ids: [profile.id])
    }

    func deleteProfiles(ids: Set<UUID>) async {
        let targets = profiles.filter { ids.contains($0.id) }
        guard !targets.isEmpty else { return }
        do {
            for target in targets {
                await disconnect(sessionID: target.id)
                await deleteProfileSecrets(target)
            }
            try await connectionStore.deleteProfiles(ids: Set(targets.map(\.id)))
            selectedProfileIDs.subtract(ids)
            await refreshProfilesAndGroups()
            if targets.count > 1 {
                statusBannerMessage = "\(strings.t("conn.deletedCountBanner")): \(targets.count)"
            }
        } catch {
            lastError = (error as? AppError) ?? .persistenceFailure(reason: error.localizedDescription)
        }
    }

    @discardableResult
    func cloneProfile(_ profile: ConnectionProfile) async -> ConnectionProfile? {
        do {
            let cloned = await buildClonedProfile(from: profile)
            try await connectionStore.saveProfile(cloned)
            await refreshProfilesAndGroups()
            selectedProfileIDs = [cloned.id]
            statusBannerMessage = "\(strings.t("conn.clonedBanner")): \(cloned.name)"
            return cloned
        } catch {
            lastError = (error as? AppError) ?? .persistenceFailure(reason: error.localizedDescription)
            return nil
        }
    }

    private func buildClonedProfile(from profile: ConnectionProfile) async -> ConnectionProfile {
        let prompt = "Clone credentials for \(profile.name)"
        let copiedPassRef = await duplicateSecret(
            profile.passwordRef,
            kind: .password,
            requireTouchID: profile.requireTouchID,
            prompt: prompt
        )
        let copiedKeyRef = await duplicateSecret(
            profile.privateKeyRef,
            kind: .privateKey,
            requireTouchID: profile.requireTouchID,
            prompt: prompt
        )
        let copiedPhraseRef = await duplicateSecret(
            profile.passphraseRef,
            kind: .keyPassphrase,
            requireTouchID: profile.requireTouchID,
            prompt: prompt
        )
        let now = Date()
        return ConnectionProfile(
            id: UUID(),
            name: nextCloneName(baseName: profile.name),
            groupID: profile.groupID,
            protocolType: profile.protocolType,
            host: profile.host,
            port: profile.port,
            username: profile.username,
            authMethod: profile.authMethod,
            passwordRef: copiedPassRef,
            privateKeyRef: copiedKeyRef,
            passphraseRef: copiedPhraseRef,
            privateKeyBookmarkData: profile.privateKeyBookmarkData,
            jumpHostProfileID: profile.jumpHostProfileID,
            proxy: profile.proxy,
            defaultRemotePath: profile.defaultRemotePath,
            defaultLocalPath: profile.defaultLocalPath,
            isFavorite: profile.isFavorite,
            requireTouchID: profile.requireTouchID,
            lastConnectedAt: nil,
            createdAt: now,
            updatedAt: now
        )
    }

    private func duplicateSecret(
        _ source: SecretReference?,
        kind: SecretReference.SecretKind,
        requireTouchID: Bool,
        prompt: String
    ) async -> SecretReference? {
        guard let source,
              let data = try? await credentialStore.loadSecret(for: source, prompt: prompt),
              !data.isEmpty
        else {
            return nil
        }
        let targetRef = SecretReference(kind: kind)
        do {
            try await credentialStore.saveSecret(data, for: targetRef, requireTouchID: requireTouchID)
            return targetRef
        } catch {
            return nil
        }
    }

    private func nextCloneName(baseName: String) -> String {
        let suffix = strings.t("conn.copySuffix")
        let candidate = "\(baseName) (\(suffix))"
        let existingNames = profiles.reduce(into: Set<String>()) { $0.insert($1.name.lowercased()) }
        if !existingNames.contains(candidate.lowercased()) {
            return candidate
        }
        var index = 2
        while existingNames.contains("\(baseName) (\(suffix) \(index))".lowercased()) {
            index += 1
        }
        return "\(baseName) (\(suffix) \(index))"
    }

    func prepareFastShutdown() {
        snapshotStreamTask?.cancel()
        snapshotStreamTask = nil
        localWatcher.stopWatching()
        for (dirURL, watcher) in remoteEditWatches {
            watcher.stopWatching()
            try? FileManager.default.removeItem(at: dirURL)
        }
        remoteEditWatches.removeAll()
        terminalManager.closeAll()
    }

    func shutdownAsyncResources() async {
        let forwarder = portForwardingManager
        let connections = activeSessions.map(\.service.connection)
        activeSessions.removeAll()
        activeSessionID = nil
        await Self.closeNetworkResources(forwarder: forwarder, connections: connections)
    }

    private nonisolated static func closeNetworkResources(
        forwarder: PortForwardingManager,
        connections: [any RemoteConnection]
    ) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await forwarder.stopAll()
            }
            for connection in connections {
                group.addTask {
                    try? await connection.disconnect(policy: .cancelAllTransfers)
                }
            }
        }
    }
}
