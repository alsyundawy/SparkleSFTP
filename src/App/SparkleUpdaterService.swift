import Foundation
import Sparkle
import SparkleCore
import SparkleSecurity

private struct GitHubReleasePayload: Decodable {
    let tagName: String
    let htmlURL: String
    let body: String?
    let draft: Bool
    let prerelease: Bool

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case body
        case draft
        case prerelease
    }
}

/// Manages Sparkle 2 Ed25519 auto-updates with strict HTTPS feed & signature enforcement (SEC-006),
/// plus TLS-verified GitHub release checking when running community or unbundled builds.
@MainActor
public final class SparkleUpdaterService {
    private var controller: SPUStandardUpdaterController?
    public private(set) var isConfiguredForSignedUpdates = false
    public let installedVersion: String

    public init() {
        let info = Bundle.main.infoDictionary ?? [:]
        installedVersion = (info["CFBundleShortVersionString"] as? String) ?? "0.3.0"
        let feedURL = info["SUFeedURL"] as? String
        let publicEDKey = info["SUPublicEDKey"] as? String
        let isPackagedApp = Bundle.main.bundleURL.pathExtension == "app"

        let hasValidFeed = UpdateConfigurationValidator.isValidHTTPSFeed(feedURL)
        let hasValidKey = UpdateConfigurationValidator.isValidEd25519PublicKey(publicEDKey)

        if isPackagedApp, hasValidFeed, hasValidKey {
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
            DiagnosticsLogger.security.info("Sparkle updater initialized in community/non-Ed25519 mode")
        }
    }

    public func applySettings(_ settings: AutoUpdateSettings) {
        guard isConfiguredForSignedUpdates, let updater = controller?.updater else { return }
        updater.automaticallyChecksForUpdates = settings.automaticallyChecks
        updater.automaticallyDownloadsUpdates = settings.automaticallyDownloads
        if settings.checkFrequency.rawValue > 0 {
            updater.updateCheckInterval = TimeInterval(settings.checkFrequency.rawValue * 3600)
        }
    }

    public func checkForUpdates(
        settings: AutoUpdateSettings = AutoUpdateSettings(),
        manual: Bool = true
    ) async -> AutoUpdateCheckStatus {
        guard UpdateConfigurationValidator.validatedHTTPSURL(settings.customFeedURL) != nil else {
            return .failed(reason: "Feed URL must use HTTPS with a valid host.")
        }

        if isConfiguredForSignedUpdates {
            applySettings(settings)
            if manual {
                controller?.checkForUpdates(nil)
            } else {
                controller?.updater.checkForUpdatesInBackground()
            }
            return .sparkleNativeTriggered
        }

        return await checkGitHubReleases(channel: settings.channel)
    }

    private func checkGitHubReleases(channel: AutoUpdateChannel) async -> AutoUpdateCheckStatus {
        guard let apiURL = URL(string: "https://api.github.com/repos/alsyundawy/SparkleSFTP/releases") else {
            return .failed(reason: "Invalid release API endpoint.")
        }
        var request = URLRequest(url: apiURL, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("SparkleSFTP/\(installedVersion)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200 ... 299).contains(http.statusCode) {
                return .failed(reason: "GitHub release check returned HTTP \(http.statusCode).")
            }
            let releases = try JSONDecoder().decode([GitHubReleasePayload].self, from: data)
            let eligible = releases.filter { !$0.draft && (channel == .beta || !$0.prerelease) }
            guard let latest = eligible.first else {
                return .upToDate(version: installedVersion)
            }
            if UpdateConfigurationValidator.isNewerVersion(latest.tagName, than: installedVersion),
               let releaseURL = UpdateConfigurationValidator.validatedHTTPSURL(latest.htmlURL) {
                let cleanVer = latest.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                return .updateAvailable(
                    version: cleanVer,
                    releaseURL: releaseURL,
                    notes: latest.body ?? ""
                )
            }
            return .upToDate(version: installedVersion)
        } catch {
            DiagnosticsLogger.security.warning(
                "Update check failed: \(error.localizedDescription, privacy: .public)"
            )
            return .failed(reason: error.localizedDescription)
        }
    }
}
