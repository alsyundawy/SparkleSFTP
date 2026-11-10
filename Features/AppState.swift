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
import UserNotifications

public struct ActiveSessionModel: Identifiable, Sendable {
    public let id: UUID
    public let profile: ConnectionProfile
    public let service: RemoteService
    public let sshClient: SSHClientService?
    public var currentRemotePath: RemotePath
    public var remoteFiles: PaginatedFileWindow
    public var sortDescriptor: FileSortDescriptor
    public var selectedRemoteFileIDs: Set<String>
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
    @Published public var localFiles: PaginatedFileWindow = PaginatedFileWindow()
    @Published public var localSortDescriptor = FileSortDescriptor()
    @Published public var selectedLocalFileIDs: Set<String> = []
    @Published public var activePane: PaneSide = .left

    @Published public var transferSnapshots: [TransferSnapshot] = []
    @Published public var trustedHosts: [String: HostTrustStore.Entry] = [:]
    @Published public var snippets: [CommandSnippet] = CommandSnippetStore.builtInDefaults
    @Published public var activeTunnels: [PortForwardingManager.ActiveTunnel] = []

    @Published public var pendingHostChallenge: HostKeyChallenge?
    @Published public var hostMismatchAlert: AppError?
    @Published public var pendingConflict: ConflictContext?
    @Published public var syncPlan: SyncPlan?
    @Published public var statusBannerMessage: String?
    @Published public var lastError: AppError?

    @Published public var language: AppLanguage = .english
    @Published public var isTerminalVisible: Bool = false
    @Published public var isTransferDrawerVisible: Bool = true
    @Published public var splitTerminalMode: Bool = false
    @Published public var maxGlobalConcurrentTransfers: Int = 3
    @Published public var maxPerHostConcurrentTransfers: Int = 2

    public var strings: AppStrings { AppStrings(language: language) }

    public let credentialStore: KeychainService
    public let hostTrustStore: HostTrustStore
    public let connectionStore: ConnectionStore
    public let localFileService: LocalFileService
    public let terminalManager: TerminalSessionManager
    public let snippetStore: CommandSnippetStore
    public let portForwardingManager: PortForwardingManager
    public let featureFlags: FeatureFlags

    var transferQueueInstance: TransferQueue?
    var snapshotStreamTask: Task<Void, Never>?
    var localWatcher = LocalDirectoryWatcher()
    var hostChallengeContinuation: CheckedContinuation<Bool, Never>?
    var conflictContinuation: CheckedContinuation<TransferConflictResolution, Never>?
    var remoteEditWatchers: [LocalDirectoryWatcher] = []
    var notifiedTerminalTransferIDs: Set<UUID> = []
    let checkUpdatesAction: @MainActor () -> Void
    let transferJournal: TransferJournal?

    public var transferQueue: TransferQueue {
        if let existing = transferQueueInstance {
            return existing
        }
        let resolver = ConflictResolver(defaultPolicy: .ask) { [weak self] context in
            guard let self else { return .skip }
            return await self.promptConflictResolution(context)
        }
        let created = TransferQueue(
            maxGlobalConcurrent: maxGlobalConcurrentTransfers,
            maxPerHostConcurrent: maxPerHostConcurrentTransfers,
            journal: transferJournal,
            conflictResolver: resolver
        ) { [weak self] profileID in
            guard let self else { throw AppError.notConnected }
            return try await self.resolveRemoteFileSystem(for: profileID)
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
        checkUpdatesAction: @escaping @MainActor () -> Void = {}
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
        self.checkUpdatesAction = checkUpdatesAction
    }

    deinit {
        snapshotStreamTask?.cancel()
        localWatcher.stopWatching()
        for watcher in remoteEditWatchers {
            watcher.stopWatching()
        }
    }

    public var currentSession: ActiveSessionModel? {
        activeSessions.first { $0.id == activeSessionID }
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

    public func resolveConflict(_ resolution: TransferConflictResolution) {
        pendingConflict = nil
        conflictContinuation?.resume(returning: resolution)
        conflictContinuation = nil
    }

    public func checkForUpdates() {
        checkUpdatesAction()
    }

    func resolveRemoteFileSystem(for profileID: UUID) throws -> any RemoteFileSystem {
        guard let session = activeSessions.first(where: { $0.profile.id == profileID }) else {
            throw AppError.notConnected
        }
        return session.service.fileSystem
    }

    func promptHostKeyChallenge(_ challenge: HostKeyChallenge) async -> Bool {
        await withCheckedContinuation { continuation in
            hostChallengeContinuation = continuation
            pendingHostChallenge = challenge
        }
    }

    func promptConflictResolution(_ context: ConflictContext) async -> TransferConflictResolution {
        await withCheckedContinuation { continuation in
            conflictContinuation = continuation
            pendingConflict = context
        }
    }

    func startTransferObserver() {
        snapshotStreamTask?.cancel()
        snapshotStreamTask = Task { [weak self] in
            guard let self else { return }
            let stream = await self.transferQueue.makeSnapshotsStream()
            for await snapshots in stream {
                if Task.isCancelled { break }
                self.transferSnapshots = snapshots
                self.notifyTerminalTransfersIfNeeded(snapshots)
            }
        }
    }

    private func notifyTerminalTransfersIfNeeded(_ snapshots: [TransferSnapshot]) {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        for snap in snapshots where !notifiedTerminalTransferIDs.contains(snap.id) {
            let content = UNMutableNotificationContent()
            switch snap.status {
            case .completed:
                content.title = "Transfer Completed"
                content.body = snap.metadata.destination.displayPath
            case .failed(let error):
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
}
