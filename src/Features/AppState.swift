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

struct ConflictPromptEntry {
    let context: ConflictContext
    let continuation: CheckedContinuation<TransferConflictResolution, Never>
}

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
    @Published public var selectedProfileIDs: Set<UUID> = []
    @Published public var searchText: String = ""

    @Published public var activeSessions: [ActiveSessionModel] = []
    @Published public var activeSessionID: UUID?
    @Published public var workspaceTabs: [WorkspaceTab]
    @Published public var activeTabID: UUID

    @Published public var quickConnectProtocol: ProtocolType = .sftp {
        didSet {
            if oldValue != quickConnectProtocol {
                let oldDefault = String(oldValue.defaultPort)
                let trimmed = quickConnectPort.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty || trimmed == oldDefault {
                    quickConnectPort = String(quickConnectProtocol.defaultPort)
                }
            }
        }
    }

    @Published public var quickConnectHost: String = ""
    @Published public var quickConnectPort: String = "22"
    @Published public var quickConnectUsername: String = "root"
    @Published public var quickConnectPassword: String = ""
    @Published public var quickConnectSaveProfile: Bool = false
    @Published public var isQuickConnectBarVisible: Bool = true

    @Published public var localCurrentURL: URL = FileManager.default.homeDirectoryForCurrentUser
    @Published public var localFiles: PaginatedFileWindow = .init()
    @Published public var localSortDescriptor = FileSortDescriptor()
    @Published public var selectedLocalFileIDs: Set<String> = []
    @Published public var localHistory = PaneNavigationHistory(
        initialPath: FileManager.default.homeDirectoryForCurrentUser.path
    )
    @Published public var activePane: PaneSide = .left

    @Published public var pendingCopyMoveRequest: CopyMoveRequest?
    @Published public var pendingChecksumReport: FileChecksumReport?
    @Published public var pendingComparisonReport: FileComparisonReport?
    @Published public var pendingCustomCommandRequest: CustomCommandRequest?

    public let transferMonitor = TransferMonitor()
    @Published public var trustedHosts: [String: HostTrustStore.Entry] = [:]
    @Published public var snippets: [CommandSnippet] = CommandSnippetStore.builtInDefaults
    @Published public var activeTunnels: [PortForwardingManager.ActiveTunnel] = []

    @Published public var pendingHostChallenge: HostKeyChallenge?
    @Published public var pendingCredentialPrompt: CredentialPromptRequest?
    @Published public var hostMismatchAlert: AppError?
    @Published public var pendingConflict: ConflictContext?
    @Published public var hasActiveConflictQueueRules: Bool = false
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
            refreshLocalizedStrings()
            savePreferencesIfLoaded()
        }
    }

    @Published public var activeLocaleCode: String = "en" {
        didSet {
            refreshLocalizedStrings()
            savePreferencesIfLoaded()
        }
    }

    @Published public var availableLocales: [LocaleDocument] {
        didSet { refreshLocalizedStrings() }
    }

    @Published public var appearanceMode: ThemeAppearanceMode = .auto {
        didSet {
            applyAppearanceToApplication()
            refreshActivePalette()
            savePreferencesIfLoaded()
        }
    }

    @Published public var selectedThemeID: String = SparkleThemeCatalog.defaultLight.id {
        didSet {
            refreshActivePalette()
            savePreferencesIfLoaded()
        }
    }

    @Published public var availableThemes: [SparkleThemePalette] {
        didSet { refreshActivePalette() }
    }

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
    @Published public var maxGlobalConcurrentTransfers: Int = 4 {
        didSet { savePreferencesIfLoaded() }
    }

    @Published public var maxPerHostConcurrentTransfers: Int = 3 {
        didSet { savePreferencesIfLoaded() }
    }

    @Published public var transferPipelineDepth: Int = 8 {
        didSet { savePreferencesIfLoaded() }
    }

    @Published public var useZlibCompression: Bool = true {
        didSet { savePreferencesIfLoaded() }
    }

    @Published public var preferredShellPath: String = ToolchainInspector.detectAvailableShells().first
        ?? "/usr/local/bin/bash" {
        didSet { savePreferencesIfLoaded() }
    }

    @Published public var externalTerminalApp: ExternalTerminalApp = .auto {
        didSet { savePreferencesIfLoaded() }
    }

    @Published public var toolchainReport = HostToolchainReport()

    @Published public var defaultConflictPolicy: TransferConflictPolicy = .ask {
        didSet { savePreferencesIfLoaded() }
    }

    @Published public var syncComparisonMode: SyncComparisonMode = .sizeAndMtime
    @Published public var syncDirection: SyncDirection = .localToRemote

    public internal(set) var strings: AppStrings
    public internal(set) var activePalette: SparkleThemePalette

    public let credentialStore: any CredentialStoreProtocol
    public let hostTrustStore: HostTrustStore
    public let connectionStore: ConnectionStore
    public let localFileService: LocalFileService
    public let terminalManager: TerminalSessionManager
    public let snippetStore: CommandSnippetStore
    public let portForwardingManager: PortForwardingManager
    public let featureFlags: FeatureFlags
    public let editorManager = EditorSessionManager()
    public let windowInstanceID = UUID()
    public var initialProfileIDForWindow: UUID?
    public var onOpenProfileInNewWindow: ((UUID) -> Void)?
    let editorWindowController = EditorWindowController()
    let aboutWindowController = AboutWindowController()

    var didBootstrap = false
    var transferQueueInstance: TransferQueue?
    var snapshotStreamTask: Task<Void, Never>?
    var localWatcher = LocalDirectoryWatcher()
    var watchedLocalURL: URL?
    var hostChallengeContinuation: CheckedContinuation<Bool, Never>?
    var credentialPromptContinuation: CheckedContinuation<String?, Never>?
    var pendingConflictQueue: [ConflictPromptEntry] = []
    var activeQueueConflictRules: [TransferConflictScope: TransferConflictPolicy] = [:]
    var remoteEditWatches: [URL: LocalDirectoryWatcher] = [:]
    var notifiedTerminalTransferIDs: Set<UUID> = []
    var connectingProfileIDs: Set<UUID> = []
    var pendingPromptedSecretToRemember: String?
    var transientQuickConnectSecrets: [String: String] = [:]
    var isSyncingPreferencesNotification = false
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
        credentialStore: any CredentialStoreProtocol = KeychainService(),
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
        let initialLocales = LocalizationCatalog.loadAvailableLocales()
        let initialThemes = SparkleThemeStore.loadAllPalettes()
        let initialStrings = AppStrings(language: .english, localeCode: "en", availableLocales: initialLocales)
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let firstTab = WorkspaceTab(
            id: UUID(),
            sessionID: nil,
            title: initialStrings.t("tabs.newTab"),
            localPath: homeDir
        )
        _workspaceTabs = Published(initialValue: [firstTab])
        _activeTabID = Published(initialValue: firstTab.id)
        _availableLocales = Published(initialValue: initialLocales)
        _availableThemes = Published(initialValue: initialThemes)
        strings = initialStrings
        activePalette = SparkleThemeCatalog.palette(
            id: SparkleThemeCatalog.defaultLight.id,
            appearanceMode: .auto,
            systemIsDark: NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua,
            available: initialThemes
        )
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
        refreshLocalizedStrings()
        refreshActivePalette()
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
}

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

    internal func resolveRemoteFileSystem(for profileID: UUID) throws -> any RemoteFileSystem {
        if let current = currentSession, current.profile.id == profileID {
            return current.service.fileSystem
        }
        guard let session = activeSessions.first(where: { $0.profile.id == profileID }) else {
            throw AppError.notConnected
        }
        return session.service.fileSystem
    }

    internal func startTransferObserver() {
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
