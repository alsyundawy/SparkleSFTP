import SparkleCore
import SparkleDesignSystem
import SparkleSecurity
import SwiftUI

public struct HostKeyVerificationSheet: View {
    @ObservedObject var appState: AppState
    let challenge: HostKeyChallenge

    public init(appState: AppState, challenge: HostKeyChallenge) {
        self.appState = appState
        self.challenge = challenge
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SparkleTheme.Spacing.medium) {
            Label(appState.strings.hostKeyUnknownTitle, systemImage: "checkmark.shield.fill")
                .font(SparkleTheme.Typography.title)
                .foregroundStyle(SparkleTheme.Colors.warning)

            Text("The authenticity of \(challenge.host):\(challenge.port) cannot be established yet.")
                .font(SparkleTheme.Typography.body)

            VStack(alignment: .leading, spacing: 4) {
                Text("Algorithm: \(challenge.algorithm)")
                Text("Fingerprint: \(challenge.fingerprintSHA256)")
            }
            .font(SparkleTheme.Typography.monoSmall)
            .padding(SparkleTheme.Spacing.small)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SparkleTheme.Colors.panelBackground)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            HStack {
                Spacer()
                Button("Reject", role: .cancel) {
                    appState.resolveHostChallenge(trusted: false)
                }
                Button("Trust & Save to Keychain") {
                    appState.resolveHostChallenge(trusted: true)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(SparkleTheme.Spacing.large)
        .frame(width: 480)
    }
}

public struct SecurityDiagnosticsView: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SparkleTheme.Spacing.medium) {
            HStack {
                Label(appState.strings.securityDiagnostics, systemImage: "lock.shield")
                    .font(SparkleTheme.Typography.title)
                Spacer()
                Button("Close") { dismiss() }
            }

            GroupBox("Security Baseline") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("• SSH Engine: apple/swift-nio-ssh >= 0.15.1 (CVE-2026-43798 mitigated)")
                    Text("• Keychain Isolation: kSecAttrAccessibleWhenUnlockedThisDeviceOnly (No iCloud sync)")
                    Text("• FTPS TLS Policy: SecTrustEvaluateWithError + OCSP + TLS 1.2+ (Zero downgrade)")
                    Text("• FTP Bridge: Clibcurl locked to ftp,ftps protocols (CVE-2025-15224 N/A)")
                }
                .font(SparkleTheme.Typography.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Trusted SSH Host Keys (TOFU)") {
                List {
                    ForEach(appState.trustedHosts.keys.sorted(), id: \.self) { hostPort in
                        if let entry = appState.trustedHosts[hostPort] {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(hostPort).font(SparkleTheme.Typography.headline)
                                    Text(entry.fingerprint).font(SparkleTheme.Typography.monoSmall)
                                }
                                Spacer()
                                Button("Revoke") {
                                    if let colonIdx = hostPort.lastIndex(of: ":"),
                                       let port = Int(hostPort[hostPort.index(after: colonIdx)...]) {
                                        let host = String(hostPort[..<colonIdx])
                                        Task {
                                            try? await appState.hostTrustStore.clearTrust(host: host, port: port)
                                            appState.trustedHosts = await appState.hostTrustStore.allTrustedHosts()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(minHeight: 160)
            }
        }
        .padding(SparkleTheme.Spacing.large)
        .frame(width: 600, height: 420)
    }
}
