import AppKit
import Foundation
import SparkleCore
import SparkleDesignSystem
import SparkleTerminal
import SparkleTransferEngine

struct InitialWorkspaceBootstrap {
    let locales: [LocaleDocument]
    let themes: [SparkleThemePalette]
    let strings: AppStrings
    let firstTab: WorkspaceTab
    let palette: SparkleThemePalette
}

struct FolderTransferCollector: Sendable {
    var taskIDs: Set<UUID> = []
    var remoteDirectories: [RemoteDirectoryPermissionTarget] = []
    var localDirectories: [LocalDirectoryPermissionTarget] = []
}

struct RemoteEditWatchRequest {
    let tempDir: URL
    let localCopy: URL
    let initialDigest: String
    let profileID: UUID
    let host: String
    let remotePath: RemotePath
}

@MainActor
private enum TransferRefreshTracker {
    static var completedIDsByWindow: [UUID: Set<UUID>] = [:]
    static var failedIDsByWindow: [UUID: Set<UUID>] = [:]
    static var debounceTasksByWindow: [UUID: Task<Void, Never>] = [:]
    static var lastRefreshAtByWindow: [UUID: Date] = [:]
}

public extension AppState {
    func reportNonCancellationError(
        _ error: Error,
        asBannerOnly: Bool = false,
        fallback: (String) -> AppError = { .transferFailed(reason: $0) }
    ) {
        if error is CancellationError {
            return
        }
        if let urlError = error as? URLError, urlError.code == .cancelled {
            return
        }
        let mapped = (error as? AppError) ?? fallback(error.localizedDescription)
        if asBannerOnly {
            statusBannerMessage = mapped.errorDescription ?? error.localizedDescription
        } else {
            lastError = mapped
        }
    }

    func openStandaloneTerminal(
        kind: StandaloneShellKind = .userDefault,
        sshProfile: ConnectionProfile? = nil
    ) {
        if let profile = sshProfile {
            do {
                _ = try standaloneTerminalManager.openSSHTab(for: profile)
            } catch {
                reportNonCancellationError(error)
                return
            }
        } else if kind == .userDefault {
            standaloneTerminalManager.ensureInitialTab(workingDirectory: localCurrentURL)
        } else {
            _ = standaloneTerminalManager.openLocalTab(kind: kind, workingDirectory: localCurrentURL)
        }
        standaloneTerminalManager.applyThemeColors(terminalThemeColors)
        standaloneTerminalWindowController.present(appState: self)
    }

    internal static func makeInitialWorkspaceBootstrap() -> InitialWorkspaceBootstrap {
        let initialLocales = LocalizationCatalog.loadAvailableLocales()
        let activeThemeID = UserDefaults.standard.string(forKey: "sparklesftp.selectedThemeID")
        let initialThemes = SparkleThemeStore.loadAllPalettes()
        let initialStrings = AppStrings(language: .english, localeCode: "en", availableLocales: initialLocales)
        let firstTab = WorkspaceTab(
            id: UUID(),
            sessionID: nil,
            title: initialStrings.t("tabs.newTab"),
            localPath: FileManager.default.homeDirectoryForCurrentUser
        )
        let targetThemeID = activeThemeID ?? SparkleThemeCatalog.defaultLight.id
        let rawMode = UserDefaults.standard.string(forKey: "sparklesftp.appearanceMode")
        let mode = rawMode.flatMap { ThemeAppearanceMode(rawValue: $0) } ?? .auto
        let palette = SparkleThemeCatalog.palette(
            id: targetThemeID,
            appearanceMode: mode,
            systemIsDark: NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua,
            available: initialThemes
        )
        return InitialWorkspaceBootstrap(
            locales: initialLocales,
            themes: initialThemes,
            strings: initialStrings,
            firstTab: firstTab,
            palette: palette
        )
    }

    func ensureAllThemesLoaded() {
        guard availableThemes.count < SparkleThemeCatalog.builtInPalettes.count else { return }
        let all = SparkleThemeStore.loadAllPalettes()
        if all.count > availableThemes.count {
            availableThemes = all
        }
    }

    var terminalThemeColors: TerminalThemeColors {
        TerminalThemeColors(
            backgroundHex: activePalette.canvasHex,
            foregroundHex: activePalette.primaryTextHex,
            caretHex: activePalette.accentHex,
            selectionHex: activePalette.borderHex
        )
    }

    func selectAdjacentWorkspaceTab(delta: Int) {
        guard workspaceTabs.count > 1,
              let currentIdx = workspaceTabs.firstIndex(where: { $0.id == activeTabID })
        else { return }
        let nextIdx = (currentIdx + delta + workspaceTabs.count) % workspaceTabs.count
        let targetID = workspaceTabs[nextIdx].id
        if let pendingURL = selectWorkspaceTabSync(id: targetID) {
            Task { await refreshLocalDirectory(pendingURL, recordHistory: false) }
        }
    }

    func promptCreateFolderShortcut() {
        if activePane == .right, currentSession == nil {
            activePane = .left
        }
        NotificationCenter.default.post(name: .sparkleRequestNewFolder, object: windowInstanceID)
    }

    func switchCommanderPaneWithFocus() {
        switchActivePane()
        let isLocal = activePane == .left
        if let window = NSApp?.keyWindow {
            NotificationCenter.default.post(
                name: .sparklePaneFocusRequested,
                object: window,
                userInfo: ["isLocal": isLocal]
            )
        }
    }

    func handleTransferSnapshotsChanged(_ snapshots: [TransferSnapshot]) {
        updateFailedTransferBannerIfNeeded(from: snapshots)
        let completed = snapshots.filter { $0.status == .completed }
        guard !completed.isEmpty else { return }

        var known = TransferRefreshTracker.completedIDsByWindow[windowInstanceID] ?? []
        var sawNewLocalDownload = false
        var sawNewRemoteUpload = false

        for item in completed where !known.contains(item.id) {
            known.insert(item.id)
            switch item.metadata.direction {
            case .download:
                sawNewLocalDownload = true
            case .upload:
                sawNewRemoteUpload = true
            }
        }
        guard sawNewLocalDownload || sawNewRemoteUpload else { return }
        TransferRefreshTracker.completedIDsByWindow[windowInstanceID] = known

        let isQueueBusy = snapshots.contains { $0.status.isActive || $0.status == .queued }
        let lastRefresh = TransferRefreshTracker.lastRefreshAtByWindow[windowInstanceID] ?? .distantPast
        if isQueueBusy, Date().timeIntervalSince(lastRefresh) < 2.0,
           TransferRefreshTracker.debounceTasksByWindow[windowInstanceID] != nil {
            return
        }

        let delay: Duration = isQueueBusy ? .seconds(2) : .milliseconds(250)
        TransferRefreshTracker.debounceTasksByWindow[windowInstanceID]?.cancel()
        TransferRefreshTracker.debounceTasksByWindow[windowInstanceID] = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            TransferRefreshTracker.lastRefreshAtByWindow[windowInstanceID] = Date()
            if sawNewLocalDownload {
                await refreshLocalDirectory(localCurrentURL, recordHistory: false)
            }
            if sawNewRemoteUpload, currentSession != nil {
                await refreshRemoteDirectory(recordHistory: false)
            }
        }
    }

    private func updateFailedTransferBannerIfNeeded(from snapshots: [TransferSnapshot]) {
        var knownFailed = TransferRefreshTracker.failedIDsByWindow[windowInstanceID] ?? []
        let activeFailedIDs = Set(snapshots.filter(\.status.isFailed).map(\.id))
        knownFailed.formIntersection(activeFailedIDs)
        let newFailures = activeFailedIDs.subtracting(knownFailed)
        TransferRefreshTracker.failedIDsByWindow[windowInstanceID] = activeFailedIDs
        if !newFailures.isEmpty {
            statusBannerMessage = "\(activeFailedIDs.count) \(strings.t("transfers.failedBannerCount"))"
        }
    }
}

extension AppState {
    func registerOrApplyFolderPermissions(_ collector: FolderTransferCollector) async {
        guard !collector.remoteDirectories.isEmpty || !collector.localDirectories.isEmpty else { return }
        let job = PendingFolderPermissionJob(
            remainingTaskIDs: collector.taskIDs,
            remoteDirectories: collector.remoteDirectories,
            localDirectories: collector.localDirectories
        )
        if job.remainingTaskIDs.isEmpty {
            await applyFolderPermissions(job)
            return
        }
        pendingFolderPermissionJobs.append(job)
        await finalizePendingFolderPermissions(from: transferQueue.currentSnapshots())
    }

    func finalizePendingFolderPermissions(from snapshots: [TransferSnapshot]) async {
        guard !pendingFolderPermissionJobs.isEmpty else { return }
        let terminalIDs = Set(snapshots.filter(\.status.isTerminal).map(\.id))
        var stillPending: [PendingFolderPermissionJob] = []
        var readyJobs: [PendingFolderPermissionJob] = []
        for var job in pendingFolderPermissionJobs {
            job.remainingTaskIDs.subtract(terminalIDs)
            if job.remainingTaskIDs.isEmpty {
                readyJobs.append(job)
            } else {
                stillPending.append(job)
            }
        }
        pendingFolderPermissionJobs = stillPending
        for job in readyJobs {
            await applyFolderPermissions(job)
        }
    }

    private func applyFolderPermissions(_ job: PendingFolderPermissionJob) async {
        let sortedRemote = job.remoteDirectories.sorted { $0.path.rawValue.count > $1.path.rawValue.count }
        for entry in sortedRemote {
            if let remoteFS = try? resolveRemoteFileSystem(for: entry.profileID) {
                try? await remoteFS.setPermissions(entry.mode & 0o777, at: entry.path)
            }
        }
        let sortedLocal = job.localDirectories.sorted { $0.url.path.count > $1.url.path.count }
        for entry in sortedLocal {
            try? FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: entry.mode & 0o777)],
                ofItemAtPath: entry.url.path
            )
        }
    }
}
