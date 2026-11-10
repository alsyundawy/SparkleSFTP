import AppKit
import SparkleFeatures
import SparklePersistence
import SparkleSecurity

/// Dependency Injection root wiring all packages into `AppState` and `SparkleUpdaterService`.
@MainActor
public final class AppEnvironment {
    public let updaterService: SparkleUpdaterService
    public let appState: AppState

    public init() {
        let updater = SparkleUpdaterService()
        self.updaterService = updater
        self.appState = AppState(
            credentialStore: KeychainService(),
            hostTrustStore: HostTrustStore(),
            connectionStore: ConnectionStore(),
            transferJournal: try? TransferJournal(),
            checkUpdatesAction: { [weak updater] in
                updater?.checkForUpdates()
            }
        )
    }

    public func shutdown() async {
        appState.terminalManager.closeAll()
        await appState.portForwardingManager.stopAll()
        for session in appState.activeSessions {
            await appState.disconnect(sessionID: session.id)
        }
    }
}
