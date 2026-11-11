import AppKit
import SparkleCore
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
        updaterService = updater
        appState = AppState(
            credentialStore: KeychainService(),
            hostTrustStore: HostTrustStore(),
            connectionStore: ConnectionStore(),
            transferJournal: try? TransferJournal(),
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
    }

    public func shutdown() async {
        appState.prepareFastShutdown()
        await appState.shutdownAsyncResources()
    }
}
