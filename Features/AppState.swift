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
    @Published public var selectedProfileIDs: Set<UUID> = []
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

    public let transferMonitor = TransferMonitor()
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
    var connectingProfileIDs: Set<UUID> = []
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
        _availableLocales = Published(initialValue: initialLocales)
        _availableThemes = Published(initialValue: initialThemes)
        strings = AppStrings(language: .english, localeCode: "en", availableLocales: initialLocales)
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
