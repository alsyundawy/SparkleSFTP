import Foundation
import Sparkle
import SparkleSecurity

/// Manages Sparkle 2 Ed25519 auto-updates with strict HTTPS feed & signature enforcement (SEC-006).
@MainActor
public final class SparkleUpdaterService {
    private var controller: SPUStandardUpdaterController?
    public private(set) var isConfiguredForSignedUpdates = false

    public init() {
        let info = Bundle.main.infoDictionary ?? [:]
        let feedURL = info["SUFeedURL"] as? String
        let publicEDKey = info["SUPublicEDKey"] as? String
        let isPackagedApp = Bundle.main.bundleURL.pathExtension == "app"

        let hasValidFeed = feedURL.map { $0.lowercased().hasPrefix("https://") } ?? false
        let hasValidKey = !(publicEDKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if isPackagedApp && hasValidFeed && hasValidKey {
            isConfiguredForSignedUpdates = true
            controller = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
            DiagnosticsLogger.security.info("Sparkle updater initialized with HTTPS feed and Ed25519 key")
        } else {
            controller = SPUStandardUpdaterController(
                startingUpdater: false,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
            DiagnosticsLogger.security.info("Sparkle updater initialized in non-packaged or unconfigured mode")
        }
    }

    public func checkForUpdates() {
        guard isConfiguredForSignedUpdates else {
            DiagnosticsLogger.security.warning(
                "Blocked Sparkle update check: missing HTTPS feed or Ed25519 SUPublicEDKey"
            )
            return
        }
        controller?.checkForUpdates(nil)
    }
}
