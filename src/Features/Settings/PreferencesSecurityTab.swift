import AppKit
import SparkleCore
import SparkleDesignSystem
import SwiftUI

struct PreferencesSecurityTab: View {
    @ObservedObject var appState: AppState
    @State private var showSecurityDiagnostics = false

    private var strings: AppStrings {
        appState.strings
    }

    var body: some View {
        ScrollView {
            Form {
                authSection
                privacySection
                hostTrustSection
                resetSection
            }
            .padding(.horizontal, SparkleTheme.Spacing.medium)
            .padding(.vertical, SparkleTheme.Spacing.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showSecurityDiagnostics) {
            SecurityDiagnosticsView(appState: appState)
        }
    }

    private var authSection: some View {
        Section(strings.t("prefs.security.authSection")) {
            Picker(
                strings.t("prefs.security.touchIDInterval"),
                selection: $appState.extendedSettings.securityTouchIDInterval
            ) {
                Text(strings.t("prefs.security.intervalEveryTime")).tag("everyTime")
                Text(strings.t("prefs.security.interval5m")).tag("5m")
                Text(strings.t("prefs.security.interval30m")).tag("30m")
                Text(strings.t("prefs.security.intervalUntilQuit")).tag("untilQuit")
            }

            Toggle(
                strings.t("prefs.security.clearOnQuit"),
                isOn: $appState.extendedSettings.securityClearKeychainCacheOnQuit
            )

            Button(strings.t("prefs.security.clearKeychainCacheNow")) {
                Task {
                    await appState.credentialStore.purgeTransientCache()
                }
            }

            let clipSeconds = appState.extendedSettings.securityAutoClearClipboardSeconds
            Stepper(
                "\(strings.t("prefs.security.clipboardTimeout")): \(clipSeconds) s",
                value: $appState.extendedSettings.securityAutoClearClipboardSeconds,
                in: 5 ... 300,
                step: 5
            )
        }
    }

    private var privacySection: some View {
        Section(strings.t("prefs.security.privacySection")) {
            Toggle(
                strings.t("prefs.security.privacyRedaction"),
                isOn: $appState.extendedSettings.securityPrivacyRedactionEnabled
            )

            let logDays = appState.extendedSettings.securityActivityLogRetentionDays
            Stepper(
                "\(strings.t("prefs.security.logRetention")): \(logDays) days",
                value: $appState.extendedSettings.securityActivityLogRetentionDays,
                in: 1 ... 90,
                step: 1
            )
        }
    }

    private var hostTrustSection: some View {
        Section(strings.t("prefs.security.hostTrustSection")) {
            HStack {
                Text("\(strings.t("prefs.security.trustedHostsCount")): \(appState.trustedHosts.count)")
                Spacer()
                Button(strings.t("prefs.security.inspectHosts")) {
                    showSecurityDiagnostics = true
                }
            }
        }
    }

    private var resetSection: some View {
        Section {
            Button(strings.t("prefs.resetTab")) {
                appState.resetSettings(for: .security)
            }
        }
    }
}
