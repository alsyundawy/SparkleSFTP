import Foundation
@testable import SparkleCore
@testable import SparkleDesignSystem
import Testing

@Suite("SparkleCore & DesignSystem Tests")
struct CoreTests {
    @Test("RemotePath normalizes slashes and dot segments safely")
    func remotePathNormalization() throws {
        let root = RemotePath(rawValue: "")
        #expect(root.rawValue == "/")
        #expect(root.isRoot)

        let path = RemotePath(rawValue: "var//www/./html/")
        #expect(path.rawValue == "/var/www/html")
        #expect(path.filename == "html")
        #expect(path.parent == RemotePath(rawValue: "/var/www"))

        let appended = try path.appending("index.html")
        #expect(appended.rawValue == "/var/www/html/index.html")
    }

    @Test("RemotePath rejects traversal and NUL components on append")
    func remotePathRejectsTraversal() {
        let base = RemotePath(rawValue: "/srv/uploads")
        #expect(throws: AppError.pathTraversal(attempted: "../etc/passwd")) {
            _ = try base.appending("../etc/passwd")
        }
        #expect(throws: AppError.pathTraversal(attempted: "bad\0name")) {
            _ = try base.appending("bad\0name")
        }
    }

    @Test("TransferProgress calculates percentage and ETA cleanly")
    func transferProgressCalculations() {
        let progress = TransferProgress(
            bytesTransferred: 500,
            totalBytes: 1000,
            bytesPerSecond: 100
        )
        #expect(progress.percentage == 0.5)
        #expect(progress.estimatedTimeRemaining == .seconds(5))

        let zero = TransferProgress(bytesTransferred: 0, totalBytes: 0, bytesPerSecond: 0)
        #expect(zero.percentage == 0)
        #expect(zero.estimatedTimeRemaining == nil)
    }

    @Test("AppError security/auth cases are marked non-retryable")
    func nonRetryableErrors() {
        #expect(AppError.hostKeyMismatch(host: "srv", expected: "a", got: "b").isNonRetryableSecurityOrAuthError)
        #expect(AppError.authenticationFailed(method: .password).isNonRetryableSecurityOrAuthError)
        #expect(AppError.tlsValidationFailed(reason: "expired").isNonRetryableSecurityOrAuthError)
        #expect(AppError.checksumMismatch(expected: "a", actual: "b").isNonRetryableSecurityOrAuthError)
        #expect(!AppError.connectionTimeout(host: "srv", seconds: 30).isNonRetryableSecurityOrAuthError)
    }

    @Test("FeatureFlags reads environment overrides deterministically")
    func featureFlagsEnvironment() {
        let flags = FeatureFlags.fromEnvironment([
            "SPARKLESFTP_SYNC_ENABLED": "0",
            "SPARKLESFTP_SCP_ENABLED": "true"
        ])
        #expect(!flags.isSyncEnabled)
        #expect(flags.isSCPFallbackEnabled)
    }

    @Test("AppStrings localizes English and Indonesian")
    func localizationStrings() {
        let englishStrings = AppStrings(language: .english)
        let indonesianStrings = AppStrings(language: .indonesian)
        #expect(englishStrings.connect == "Connect")
        #expect(indonesianStrings.connect == "Hubungkan")
    }
}
