import Foundation
import SparkleCore
import SparkleDesignSystem
import SparkleFileManager

public extension AppState {
    var currentTab: WorkspaceTab? {
        workspaceTabs.first { $0.id == activeTabID }
    }

    func broadcastConnectionsDidChange() {
        NotificationCenter.default.post(name: .sparkleConnectionsDidChange, object: windowInstanceID)
    }

    func syncCurrentTabLocalSnapshot() {
        guard let idx = workspaceTabs.firstIndex(where: { $0.id == activeTabID }) else { return }
        workspaceTabs[idx].localPath = localCurrentURL
        workspaceTabs[idx].localHistory = localHistory
        workspaceTabs[idx].localSortDescriptor = localSortDescriptor
    }

    @discardableResult
    func openNewWorkspaceTab() -> WorkspaceTab {
        syncCurrentTabLocalSnapshot()
        let title = nextEmptyTabTitle()
        let tab = WorkspaceTab(
            id: UUID(),
            sessionID: nil,
            title: title,
            localPath: localCurrentURL
        )
        workspaceTabs.append(tab)
        activeTabID = tab.id
        activeSessionID = nil
        localHistory = tab.localHistory
        localSortDescriptor = tab.localSortDescriptor
        return tab
    }

    private func nextEmptyTabTitle() -> String {
        let baseTitle = strings.t("tabs.newTab")
        let existingTitles = Set(workspaceTabs.map(\.title))
        if !existingTitles.contains(baseTitle) {
            return baseTitle
        }
        var suffix = 2
        while existingTitles.contains("\(baseTitle) #\(suffix)") {
            suffix += 1
        }
        return "\(baseTitle) #\(suffix)"
    }

    @discardableResult
    func selectWorkspaceTabSync(id: UUID) -> URL? {
        guard id != activeTabID,
              let target = workspaceTabs.first(where: { $0.id == id })
        else { return nil }

        syncCurrentTabLocalSnapshot()
        activeTabID = target.id
        activeSessionID = target.sessionID
        localHistory = target.localHistory
        localSortDescriptor = target.localSortDescriptor
        if target.sessionID != nil {
            activePane = .right
        }
        if target.localPath.standardizedFileURL != localCurrentURL.standardizedFileURL {
            return target.localPath
        }
        return nil
    }

    func selectWorkspaceTab(id: UUID) async {
        if let pendingURL = selectWorkspaceTabSync(id: id) {
            await refreshLocalDirectory(pendingURL, recordHistory: false)
        }
    }

    func closeWorkspaceTabSync(id: UUID) -> (removedSessionID: UUID?, pendingLocalRefresh: URL?) {
        guard let idx = workspaceTabs.firstIndex(where: { $0.id == id }) else {
            return (nil, nil)
        }
        let removedSessionID = workspaceTabs[idx].sessionID

        if workspaceTabs.count == 1 {
            workspaceTabs[0].sessionID = nil
            workspaceTabs[0].title = strings.t("tabs.newTab")
            activeTabID = workspaceTabs[0].id
            activeSessionID = nil
            return (removedSessionID, nil)
        }

        let wasActive = (activeTabID == id)
        workspaceTabs.remove(at: idx)
        var pendingLocalRefresh: URL?
        if wasActive {
            let nextIndex = min(idx, workspaceTabs.count - 1)
            let nextTab = workspaceTabs[nextIndex]
            activeTabID = nextTab.id
            activeSessionID = nextTab.sessionID
            localHistory = nextTab.localHistory
            localSortDescriptor = nextTab.localSortDescriptor
            if nextTab.sessionID != nil {
                activePane = .right
            }
            if nextTab.localPath.standardizedFileURL != localCurrentURL.standardizedFileURL {
                pendingLocalRefresh = nextTab.localPath
            }
        }
        return (removedSessionID, pendingLocalRefresh)
    }

    func closeWorkspaceTab(id: UUID) async {
        let outcome = closeWorkspaceTabSync(id: id)
        if let removedSessionID = outcome.removedSessionID {
            await disconnect(sessionID: removedSessionID)
        }
        if let pendingLocalRefresh = outcome.pendingLocalRefresh {
            await refreshLocalDirectory(pendingLocalRefresh, recordHistory: false)
        }
    }

    func closeOtherWorkspaceTabs(keeping id: UUID) async {
        await selectWorkspaceTab(id: id)
        let otherIDs = workspaceTabs.filter { $0.id != id }.map(\.id)
        for otherID in otherIDs {
            await closeWorkspaceTab(id: otherID)
        }
    }

    func duplicateWorkspaceTab(id: UUID) async {
        guard let tab = workspaceTabs.first(where: { $0.id == id }) else {
            openNewWorkspaceTab()
            return
        }
        if let sessionID = tab.sessionID,
           let session = activeSessions.first(where: { $0.id == sessionID }) {
            await connect(profile: session.profile, openInNewTab: true)
        } else {
            openNewWorkspaceTab()
        }
    }

    func reconnectWorkspaceTab(id: UUID) async {
        guard let tab = workspaceTabs.first(where: { $0.id == id }),
              let sessionID = tab.sessionID,
              let session = activeSessions.first(where: { $0.id == sessionID })
        else { return }
        let profile = session.profile
        await selectWorkspaceTab(id: id)
        await disconnect(sessionID: sessionID)
        await connect(profile: profile, openInNewTab: false)
    }

    func openProfileInNewWindow(_ profileID: UUID) {
        onOpenProfileInNewWindow?(profileID)
    }

    func performQuickConnect() async {
        let trimmedHost = quickConnectHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else { return }
        let parsedPort = Int(quickConnectPort.trimmingCharacters(in: .whitespacesAndNewlines))
            ?? quickConnectProtocol.defaultPort
        let trimmedUser = quickConnectUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedUser = trimmedUser.isEmpty ? "root" : trimmedUser
        let enteredSecret = quickConnectPassword
        let profile = ConnectionProfile(
            name: trimmedHost,
            protocolType: quickConnectProtocol,
            host: trimmedHost,
            port: parsedPort,
            username: resolvedUser,
            authMethod: .password
        )
        if quickConnectSaveProfile {
            await saveProfile(profile, secretString: enteredSecret.isEmpty ? nil : enteredSecret)
        } else if !enteredSecret.isEmpty {
            let key = "\(trimmedHost):\(parsedPort):\(resolvedUser)"
            transientQuickConnectSecrets[key] = enteredSecret
        }
        await connect(profile: profile, openInNewTab: currentTab?.sessionID != nil)
    }

    func attachConnectedSession(_ session: ActiveSessionModel, openInNewTab: Bool) {
        let title = disambiguatedTabTitle(for: session.profile)
        if !openInNewTab,
           let activeIdx = workspaceTabs.firstIndex(where: { $0.id == activeTabID }),
           workspaceTabs[activeIdx].sessionID == nil {
            workspaceTabs[activeIdx].sessionID = session.id
            workspaceTabs[activeIdx].title = title
            workspaceTabs[activeIdx].localPath = localCurrentURL
            workspaceTabs[activeIdx].localHistory = localHistory
            workspaceTabs[activeIdx].localSortDescriptor = localSortDescriptor
        } else {
            syncCurrentTabLocalSnapshot()
            let tab = WorkspaceTab(
                id: UUID(),
                sessionID: session.id,
                title: title,
                localPath: localCurrentURL,
                localHistory: localHistory,
                localSortDescriptor: localSortDescriptor
            )
            workspaceTabs.append(tab)
            activeTabID = tab.id
        }
    }

    private func disambiguatedTabTitle(for profile: ConnectionProfile) -> String {
        let existingCount = activeSessions.count { $0.profile.name == profile.name }
        if existingCount <= 1 {
            return profile.name
        }
        return "\(profile.name) (#\(existingCount))"
    }
}
