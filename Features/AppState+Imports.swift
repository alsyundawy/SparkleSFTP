import Foundation
import SparkleCore
import SparklePersistence
import SparkleSynchronization

public extension AppState {
    func openTerminalTab() async {
        guard let session = currentSession else { return }
        isTerminalVisible = true
        do {
            _ = try await terminalManager.openSession(title: session.profile.name, sshClient: session.sshClient)
        } catch {
            lastError = (error as? AppError) ?? .transferFailed(reason: error.localizedDescription)
        }
    }

    func startPortForwarding(_ rule: PortForwardingRule) async {
        guard let sshClient = currentSession?.sshClient else {
            lastError = .notConnected
            return
        }
        do {
            _ = try await portForwardingManager.startForward(rule: rule, sshClient: sshClient)
            activeTunnels = await portForwardingManager.activeTunnels()
        } catch {
            lastError = (error as? AppError) ?? .transferFailed(reason: error.localizedDescription)
        }
    }

    func stopPortForwarding(id: UUID) async {
        await portForwardingManager.stopTunnel(id: id)
        activeTunnels = await portForwardingManager.activeTunnels()
    }

    func prepareSyncDryRun(
        exclusions: [String],
        deleteExtras: Bool,
        direction: SyncDirection? = nil,
        mode: SyncComparisonMode = .sizeAndMtime
    ) async {
        guard let session = currentSession else { return }
        do {
            let resolvedDirection = direction ?? syncDirection
            let localScanned = try await DirectoryScanner.scanLocal(
                rootURL: localCurrentURL,
                exclusionGlobs: exclusions,
                includeSHA256: mode == .sha256Strict
            )
            let remoteScanned = try await DirectoryScanner.scanRemote(
                rootPath: session.currentRemotePath,
                remoteFS: session.service.fileSystem,
                exclusionGlobs: exclusions
            )
            syncPlan = SyncPlanner.buildPlan(
                source: localScanned,
                destination: remoteScanned,
                direction: resolvedDirection,
                mode: mode,
                deleteExtras: deleteExtras
            )
        } catch {
            lastError = (error as? AppError) ?? .transferFailed(reason: error.localizedDescription)
        }
    }

    func executeSyncPlan(dryRun: Bool) async {
        guard let session = currentSession, let plan = syncPlan else { return }
        let executor = SyncExecutor(transferQueue: transferQueue)
        let target = SyncExecutionTarget(
            localRoot: localCurrentURL,
            remoteRoot: session.currentRemotePath,
            profileID: session.profile.id,
            host: session.profile.host,
            remoteFS: session.service.fileSystem
        )
        do {
            let report = try await executor.execute(plan: plan, target: target, dryRun: dryRun)
            statusBannerMessage = dryRun
                ? "Dry-run validated \(plan.actions.count) actions"
                : "Dispatched \(report.appliedCount) sync actions"
            syncPlan = nil
            if !dryRun {
                await refreshRemoteDirectory(recordHistory: false)
            }
        } catch {
            lastError = (error as? AppError) ?? .transferFailed(reason: error.localizedDescription)
        }
    }

    func addSnippet(title: String, command: String, category: String = "Custom") async {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCmd = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !trimmedCmd.isEmpty else { return }
        snippets.append(CommandSnippet(title: trimmedTitle, command: trimmedCmd, category: category))
        try? await snippetStore.saveSnippets(snippets)
    }

    func deleteSnippet(id: UUID) async {
        snippets.removeAll { $0.id == id }
        try? await snippetStore.saveSnippets(snippets)
    }

    func importFromSSHConfig() async {
        let sshConfigURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh/config")
        guard let contents = try? String(contentsOf: sshConfigURL, encoding: .utf8) else {
            lastError = .fileNotFound(path: sshConfigURL.path)
            return
        }
        let entries = SSHConfigParser.parse(contents: contents)
        for entry in entries {
            await saveProfile(entry.toConnectionProfile(), secretString: nil)
        }
    }

    func inspectExternalConnections(from url: URL) {
        do {
            let report = try ExternalConnectionFileReader.inspect(url: url)
            pendingImportReport = report
            isShowingImportSheet = true
        } catch {
            lastError = (error as? AppError) ?? .persistenceFailure(reason: error.localizedDescription)
        }
    }

    func importExternalConnections(from url: URL) async {
        do {
            let report = try ExternalConnectionFileReader.inspect(url: url)
            await commitImportedConnections(report.connections, createGroups: true, skipDuplicates: false)
        } catch {
            lastError = (error as? AppError) ?? .persistenceFailure(reason: error.localizedDescription)
        }
    }

    func commitImportedConnections(
        _ entries: [ImportedConnection],
        createGroups: Bool,
        skipDuplicates: Bool
    ) async {
        do {
            var groupByName = Dictionary(uniqueKeysWithValues: groups.map { ($0.name.lowercased(), $0) })
            var existingKeys = Set(profiles.map {
                "\($0.protocolType.rawValue)|\($0.host.lowercased())|\($0.port)|\($0.username.lowercased())"
            })
            var importedCount = 0

            for item in entries {
                var profile = item.profile
                let key = "\(profile.protocolType.rawValue)|"
                    + "\(profile.host.lowercased())|\(profile.port)|"
                    + "\(profile.username.lowercased())"
                if skipDuplicates, existingKeys.contains(key) {
                    continue
                }
                existingKeys.insert(key)

                if createGroups, let rawGroup = item.groupName, !rawGroup.isEmpty {
                    let normalized = rawGroup.lowercased()
                    if let matched = groupByName[normalized] {
                        profile.groupID = matched.id
                    } else {
                        let newGroup = ServerGroup(name: rawGroup, sortOrder: groupByName.count)
                        try await connectionStore.saveGroup(newGroup)
                        groupByName[normalized] = newGroup
                        profile.groupID = newGroup.id
                    }
                }

                if let secret = item.transientSecret {
                    let ref = profile.passwordRef ?? SecretReference(kind: .password)
                    try await credentialStore.saveSecret(secret, for: ref, requireTouchID: false)
                    profile.passwordRef = ref
                }
                try await connectionStore.saveProfile(profile)
                importedCount += 1
            }
            await refreshProfilesAndGroups()
            statusBannerMessage = "Imported \(importedCount) connection(s)"
        } catch {
            lastError = (error as? AppError) ?? .persistenceFailure(reason: error.localizedDescription)
        }
    }
}
