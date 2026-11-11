import AppKit
import SparkleCore
import SparkleFeatures
import SparklePersistence
import SparkleSecurity
import SparkleTerminal

@MainActor
private final class WeakAppStateBox {
    weak var state: AppState?

    init(_ state: AppState) {
        self.state = state
    }
}

/// Shared service factory producing independent per-window `AppState` sessions backed by shared persistent stores.
@MainActor
public final class AppEnvironment {
    public let updaterService: SparkleUpdaterService
    public let credentialStore: KeychainService
    public let hostTrustStore: HostTrustStore
    public let connectionStore: ConnectionStore
    public let transferJournal: TransferJournal?
    public let snippetStore: CommandSnippetStore
    public let portForwardingManager: PortForwardingManager

    private var windowBoxes: [WeakAppStateBox] = []
    public private(set) lazy var settingsFallbackState: AppState = makeWindowState()

    public init() {
        updaterService = SparkleUpdaterService()
        credentialStore = KeychainService()
        hostTrustStore = HostTrustStore()
        connectionStore = ConnectionStore()
        transferJournal = try? TransferJournal()
        snippetStore = CommandSnippetStore()
        portForwardingManager = PortForwardingManager()
    }

    public func makeWindowState() -> AppState {
        let updater = updaterService
        let state = AppState(
            credentialStore: credentialStore,
            hostTrustStore: hostTrustStore,
            connectionStore: connectionStore,
            transferJournal: transferJournal,
            snippetStore: snippetStore,
            portForwardingManager: portForwardingManager,
            installedAppVersion: updater.installedVersion,
            isSignedUpdatesReady: updater.isConfiguredForSignedUpdates,
            performUpdateCheckAction: { [weak updater] settings, manual in
                guard let updater else {
                    return .failed(reason: "Updater unavailable")
                }
                return await updater.checkForUpdates(settings: settings, manual: manual)
            },
            applyAutoUpdateSettingsAction: { [weak updater] settings in
                updater?.applySettings(settings)
            }
        )
        pruneAndRegister(state)
        return state
    }

    public var hasActiveAsyncCleanup: Bool {
        pruneAndActiveStates().contains { $0.hasActiveAsyncCleanup }
    }

    public func prepareFastShutdown() {
        for state in pruneAndActiveStates() {
            state.prepareFastShutdown()
        }
    }

    public func shutdown() async {
        let activeStates = pruneAndActiveStates()
        for state in activeStates {
            state.prepareFastShutdown()
        }
        for state in activeStates {
            await state.shutdownAsyncResources()
        }
    }

    private func pruneAndRegister(_ state: AppState) {
        windowBoxes.removeAll { $0.state == nil }
        windowBoxes.append(WeakAppStateBox(state))
    }

    private func pruneAndActiveStates() -> [AppState] {
        windowBoxes.removeAll { $0.state == nil }
        return windowBoxes.compactMap(\.state)
    }
}
