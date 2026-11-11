import AppKit
import Foundation
import SparkleCore
import SparkleDesignSystem
import SparkleFileManager
import SparkleNetworking
import SparklePersistence
import SparkleSecurity
import SparkleSynchronization
import SparkleTerminal
import SparkleTransferEngine

public struct ActiveSessionModel: Identifiable, Sendable {
    public let id: UUID
    public let profile: ConnectionProfile
    public let service: RemoteService
    public let sshClient: SSHClientService?
    public var currentRemotePath: RemotePath
    public var remoteFiles: PaginatedFileWindow
    public var sortDescriptor: FileSortDescriptor
    public var selectedRemoteFileIDs: Set<String>
    public var history: PaneNavigationHistory

    public init(
        id: UUID,
        profile: ConnectionProfile,
        service: RemoteService,
        sshClient: SSHClientService?,
        currentRemotePath: RemotePath,
        remoteFiles: PaginatedFileWindow,
        sortDescriptor: FileSortDescriptor,
        selectedRemoteFileIDs: Set<String>,
        history: PaneNavigationHistory? = nil
    ) {
        self.id = id
        self.profile = profile
        self.service = service
        self.sshClient = sshClient
        self.currentRemotePath = currentRemotePath
        self.remoteFiles = remoteFiles
        self.sortDescriptor = sortDescriptor
        self.selectedRemoteFileIDs = selectedRemoteFileIDs
        self.history = history ?? PaneNavigationHistory(initialPath: currentRemotePath.rawValue)
    }
}

/// Root presentation coordinator isolating Views from networking/Keychain internals (macOS 13+ ObservableObject).
@MainActor
public final class AppState: ObservableObject {
    @Published public var profiles: [ConnectionProfile] = []
    @Published public var groups: [ServerGroup] = []
    @Published public var selectedProfileID: UUID?
    @Published public var searchText: String = ""

    @Published public var activeSessions: [ActiveSessionModel] = []
    @Published public var activeSessionID: UUID?

    @Published public var localCurrentURL: URL = FileManager.default.homeDirectoryForCurrentUser
    @Published public var localFiles: PaginatedFileWindow = .init()
    @Published public var localSortDescriptor = FileSortDescriptor()
    @Published public var selectedLocalFileIDs: Set<String> = []
    @Published public var localHistory = PaneNavigationHistory(
        initialPath: FileManager.default.homeDirectoryForCurrentUser.path
    )
    @Published public var activePane: PaneSide = .left

    @Published public var transferSnapshots: [TransferSnapshot] = []
    @Published public var trustedHosts: [String: HostTrustStore.Entry] = [:]
    @Published public var snippets: [CommandSnippet] = CommandSnippetStore.builtInDefaults
    @Published public var activeTunnels: [PortForwardingManager.ActiveTunnel] = []

    @Published public var pendingHostChallenge: HostKeyChallenge?
    @Published public var pendingCredentialPrompt: CredentialPromptRequest?
    @Published public var hostMismatchAlert: AppError?
    @Published public var pendingConflict: ConflictContext?
    @Published public var pendingImportReport: ExternalImportReport?
    @Published public var isShowingImportSheet: Bool = false
    @Published public var syncPlan: SyncPlan?
    @Published public var statusBannerMessage: String?
    @Published public var lastError: AppError?

    @Published public var language: AppLanguage = .english {
        didSet {
            if activeLocaleCode != language.rawValue {
                activeLocaleCode = language.rawValue
            }
            savePreferencesIfLoaded()
        }
    }

    @Published public var activeLocaleCode: String = "en" {
        didSet { savePreferencesIfLoaded() }
    }

    @Published public var availableLocales: [LocaleDocument] = LocalizationCatalog.loadAvailableLocales()

    @Published public var appearanceMode: ThemeAppearanceMode = .auto {
        didSet {
            applyAppearanceToApplication()
            savePreferencesIfLoaded()
        }
    }

    @Published public var selectedThemeID: String = SparkleThemeCatalog.defaultLight.id {
        didSet { savePreferencesIfLoaded() }
    }

    @Published public var availableThemes: [SparkleThemePalette] = SparkleThemeStore.loadAllPalettes()

    @Published public var autoUpdateSettings = AutoUpdateSettings() {
        didSet { savePreferencesIfLoaded() }
    }

    @Published public var autoUpdateStatus: AutoUpdateCheckStatus = .idle
    @Published public var isSignedUpdatesReady: Bool = false
    @Published public var installedAppVersion: String

    @Published public var openDoubleClickInInternalEditor: Bool = true {
        didSet { savePreferencesIfLoaded() }
    }

    @Published public var isTerminalVisible: Bool = false
    @Published public var isTransferDrawerVisible: Bool = true
    @Published public var splitTerminalMode: Bool = false
    @Published public var maxGlobalConcurrentTransfers: Int = 3 {
        didSet { savePreferencesIfLoaded() }
    }

    @Published public var maxPerHostConcurrentTransfers: Int = 2 {
        didSet { savePreferencesIfLoaded() }
    }

    @Published public var defaultConflictPolicy: TransferConflictPolicy = .ask {
        didSet { savePreferencesIfLoaded() }
    }

    @Published public var syncComparisonMode: SyncComparisonMode = .sizeAndMtime
    @Published public var syncDirection: SyncDirection = .localToRemote

    public var strings: AppStrings {
        AppStrings(language: language, localeCode: activeLocaleCode, availableLocales: availableLocales)
    }

    public var activePalette: SparkleThemePalette {
        let isDarkSystem = NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return SparkleThemeCatalog.palette(
            id: selectedThemeID,
            appearanceMode: appearanceMode,
            systemIsDark: isDarkSystem,
            available: availableThemes
        )
    }

    public let credentialStore: KeychainService
    public let hostTrustStore: HostTrustStore
    public let connectionStore: ConnectionStore
    public let localFileService: LocalFileService
    public let terminalManager: TerminalSessionManager
    public let snippetStore: CommandSnippetStore
    public let portForwardingManager: PortForwardingManager
    public let featureFlags: FeatureFlags
    public let editorManager = EditorSessionManager()
    let editorWindowController = EditorWindowController()

    var transferQueueInstance: TransferQueue?
    var snapshotStreamTask: Task<Void, Never>?
    var localWatcher = LocalDirectoryWatcher()
    var watchedLocalURL: URL?
    var hostChallengeContinuation: CheckedContinuation<Bool, Never>?
    var credentialPromptContinuation: CheckedContinuation<String?, Never>?
    var conflictContinuation: CheckedContinuation<TransferConflictResolution, Never>?
    var remoteEditWatches: [URL: LocalDirectoryWatcher] = [:]
    var notifiedTerminalTransferIDs: Set<UUID> = []
    var didLoadPreferences = false
    let performUpdateCheckAction: @MainActor (AutoUpdateSettings, Bool) async -> AutoUpdateCheckStatus
    let applyAutoUpdateSettingsAction: @MainActor (AutoUpdateSettings) -> Void
    let transferJournal: TransferJournal?

    public var transferQueue: TransferQueue {
        if let existing = transferQueueInstance {
            return existing
        }
        let resolver = ConflictResolver(defaultPolicy: defaultConflictPolicy) { [weak self] context in
            guard let self else { return .skip }
            return await promptConflictResolution(context)
        }
        let created = TransferQueue(
            maxGlobalConcurrent: maxGlobalConcurrentTransfers,
            maxPerHostConcurrent: maxPerHostConcurrentTransfers,
            journal: transferJournal,
            conflictResolver: resolver
        ) { [weak self] profileID in
            guard let self else { throw AppError.notConnected }
            return try await resolveRemoteFileSystem(for: profileID)
        }
        transferQueueInstance = created
        return created
    }

    public init(
        credentialStore: KeychainService = KeychainService(),
        hostTrustStore: HostTrustStore = HostTrustStore(),
        connectionStore: ConnectionStore = ConnectionStore(),
        transferJournal: TransferJournal? = try? TransferJournal(),
        localFileService: LocalFileService = LocalFileService(),
        terminalManager: TerminalSessionManager = TerminalSessionManager(),
        snippetStore: CommandSnippetStore = CommandSnippetStore(),
        portForwardingManager: PortForwardingManager = PortForwardingManager(),
        featureFlags: FeatureFlags = .fromEnvironment(),
        installedAppVersion: String? = nil,
        isSignedUpdatesReady: Bool = false,
        performUpdateCheckAction: @escaping @MainActor (AutoUpdateSettings, Bool) async
            -> AutoUpdateCheckStatus = { _, _ in
                .upToDate(version: "0.2.0")
            },
        applyAutoUpdateSettingsAction: @escaping @MainActor (AutoUpdateSettings) -> Void = { _ in }
    ) {
        self.credentialStore = credentialStore
        self.hostTrustStore = hostTrustStore
        self.connectionStore = connectionStore
        self.transferJournal = transferJournal
        self.localFileService = localFileService
        self.terminalManager = terminalManager
        self.snippetStore = snippetStore
        self.portForwardingManager = portForwardingManager
        self.featureFlags = featureFlags
        let bundleVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        self.installedAppVersion = installedAppVersion ?? bundleVersion ?? "0.2.0"
        self.isSignedUpdatesReady = isSignedUpdatesReady
        self.performUpdateCheckAction = performUpdateCheckAction
        self.applyAutoUpdateSettingsAction = applyAutoUpdateSettingsAction
        loadPersistedPreferences()
        applyAppearanceToApplication()
    }

    deinit {
        snapshotStreamTask?.cancel()
        localWatcher.stopWatching()
        for (dirURL, watcher) in remoteEditWatches {
            watcher.stopWatching()
            try? FileManager.default.removeItem(at: dirURL)
        }
    }

    public var currentSession: ActiveSessionModel? {
        activeSessions.first { $0.id == activeSessionID }
    }

    public var recentProfiles: [ConnectionProfile] {
        profiles
            .filter { $0.lastConnectedAt != nil }
            .sorted { ($0.lastConnectedAt ?? .distantPast) > ($1.lastConnectedAt ?? .distantPast) }
    }

    public var filteredProfiles: [ConnectionProfile] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return profiles }
        return profiles.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
                || $0.host.localizedCaseInsensitiveContains(trimmed)
                || $0.username.localizedCaseInsensitiveContains(trimmed)
        }
    }

    public func resolveHostChallenge(trusted: Bool) {
        pendingHostChallenge = nil
        hostChallengeContinuation?.resume(returning: trusted)
        hostChallengeContinuation = nil
    }

    public func resolveCredentialPrompt(_ secret: String?) {
        pendingCredentialPrompt = nil
        credentialPromptContinuation?.resume(returning: secret)
        credentialPromptContinuation = nil
    }

    public func resolveConflict(_ resolution: TransferConflictResolution) {
        pendingConflict = nil
        conflictContinuation?.resume(returning: resolution)
        conflictContinuation = nil
    }

    func resolveRemoteFileSystem(for profileID: UUID) throws -> any RemoteFileSystem {
        guard let session = activeSessions.first(where: { $0.profile.id == profileID }) else {
            throw AppError.notConnected
        }
        return session.service.fileSystem
    }

    func startTransferObserver() {
        snapshotStreamTask?.cancel()
        snapshotStreamTask = Task { [weak self] in
            guard let self else { return }
            let stream = await transferQueue.makeSnapshotsStream()
            for await snapshots in stream {
                if Task.isCancelled {
                    break
                }
                transferSnapshots = snapshots
                notifyTerminalTransfersIfNeeded(snapshots)
            }
        }
    }
}
